import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/data/auth_session.dart';
import '../config/app_config.dart';
import '../http/api_exception.dart';
import '../http/error_mapping_interceptor.dart';
import '../http/token_storage.dart';
import 'auth_state.dart';

/// Controlador de sessão consumido pelo `go_router` para redirect e pelos
/// shells para decidir qual navegação mostrar.
///
/// Liga ao `identity` de verdade (P0.6): no boot, tenta restaurar a sessão
/// do [TokenStorage] revalidando-a com um refresh (garante que o access
/// token devolvido ao resto do app está sempre fresco). **Falha de rede no
/// boot não desloga** (P1.8): só uma recusa do servidor limpa a sessão.
/// Chamadas de
/// login/signup/accept invite persistem a sessão nova; o refresh usado pelo
/// [AuthInterceptor] das demais chamadas HTTP passa por [refreshSession].
class AuthController extends Notifier<AuthState> {
  AuthController({TokenStorage? tokenStorage, HttpClientAdapter? httpAdapter})
      : _injectedTokenStorage = tokenStorage,
        _injectedHttpAdapter = httpAdapter;

  /// Injeções usadas só em teste de widget (evita depender do backend real
  /// e do plugin de secure storage por platform channel).
  final TokenStorage? _injectedTokenStorage;
  final HttpClientAdapter? _injectedHttpAdapter;

  late final TokenStorage _tokenStorage;
  late final AuthRepository _authRepository;

  @override
  AuthState build() {
    _tokenStorage = _injectedTokenStorage ?? TokenStorage();
    // Dio "cru": só para o próprio fluxo de auth, sem os interceptors do
    // ApiClient (que dependeriam deste mesmo controller para refresh —
    // evita recursão). Erros ainda viram ApiException via
    // ErrorMappingInterceptor, reaproveitado isoladamente aqui.
    _authRepository = AuthRepository(_rawIdentityDio());

    _restoreSession();
    return const AuthState.unknown();
  }

  Future<void> _restoreSession() async {
    final StoredSession? stored;
    try {
      stored = await _tokenStorage.readSession();
    } catch (_) {
      // Armazenamento ilegível não pode prender o app no splash (A10): sem
      // sessão legível, o caminho é o login.
      state = const AuthState.unauthenticated();
      return;
    }
    if (stored == null) {
      state = const AuthState.unauthenticated();
      return;
    }

    try {
      final session = await _authRepository.refresh(
        refreshToken: stored.tokens.refreshToken,
        tenantId: stored.tenantId,
      );
      await _applySession(session);
    } on ApiException catch (e) {
      if (e.code == 'network_error') {
        // Sem rede o refresh não prova **nada** sobre a sessão. Derrubá-la
        // trancaria o aluno para fora do treino já baixado e da fila de
        // execução — exatamente o que o ADR-003 §1 promete manter de pé —, e
        // sem rede ele nem consegue entrar de novo para destravar a fila.
        // A sessão guardada segue valendo; o AuthInterceptor renova o access
        // token na primeira chamada com rede.
        state = AuthState.authenticated(
          roles: userRolesFrom(stored.roles),
          tenantId: stored.tenantId,
          userId: stored.userId,
          isOwner: stored.roles.contains('owner'),
        );
        return;
      }
      await _tokenStorage.clear();
      state = const AuthState.unauthenticated();
    } catch (_) {
      await _tokenStorage.clear();
      state = const AuthState.unauthenticated();
    }
  }

  /// Login. Propaga [ApiException] `multiple_tenants` para a tela escolher
  /// o tenant e chamar de novo com `tenantId`.
  Future<void> signIn({
    required String email,
    required String password,
    String? tenantId,
  }) async {
    final session = await _authRepository.login(
      email: email,
      password: password,
      tenantId: tenantId,
    );
    await _applySession(session);
  }

  Future<void> signUpTenant({
    required String businessName,
    required String slug,
    required String name,
    required String email,
    required String password,
  }) async {
    final session = await _authRepository.signup(
      businessName: businessName,
      slug: slug,
      name: name,
      email: email,
      password: password,
      // O formulário só deixa chegar aqui com o aceite marcado (ADR-008 §6).
      termsVersion: AppConfig.termsVersion,
    );
    await _applySession(session);
  }

  /// [consents] são as finalidades marcadas no aceite (`health_data`
  /// obrigatória para o aluno, `progress_photos` opcional — ADR-008 §1).
  Future<void> acceptInvite({
    required String token,
    required String password,
    required Map<String, bool> consents,
  }) async {
    final session = await _authRepository.acceptInvite(
      token: token,
      password: password,
      termsVersion: AppConfig.termsVersion,
      consents: consents,
    );
    await _applySession(session);
  }

  Future<void> forgotPassword({required String email}) {
    return _authRepository.forgotPassword(email: email);
  }

  Future<void> resetPassword({
    required String token,
    required String password,
  }) {
    return _authRepository.resetPassword(token: token, password: password);
  }

  Future<void> signOut() async {
    final stored = await _tokenStorage.readSession();
    await _tokenStorage.clear();
    state = const AuthState.unauthenticated();
    if (stored != null) {
      // Revogação best-effort: a sessão local já foi limpa independentemente
      // do resultado desta chamada.
      try {
        await _authRepository.logout(
          refreshToken: stored.tokens.refreshToken,
          tenantId: stored.tenantId,
        );
      } catch (_) {
        // Ignorado: usuário já está deslogado localmente.
      }
    }
  }

  /// Usado apenas em testes de widget que não sobem o backend real (ex.:
  /// exercitar o roteamento por papel sem depender de HTTP).
  void signInStub(
    Set<UserRole> roles, {
    bool isOwner = false,
    bool consentPending = false,
  }) {
    state = AuthState.authenticated(
      roles: roles,
      isOwner: isOwner,
      tenantId: 'stub-tenant',
      userId: 'stub-user',
      consentPending: consentPending,
    );
  }

  /// Alterna o contexto ativo (professor ↔ aluno) para quem tem os dois
  /// papéis — usado pelo seletor no app bar.
  void switchContext(ActiveContext context) {
    if (!state.isAuthenticated) return;
    state = state.copyWith(activeContext: context);
  }

  /// Chamado pelo [AuthInterceptor] de qualquer `ApiClient` (não só o do
  /// próprio auth) quando uma requisição toma 401. Reusa a mesma sessão
  /// persistida — todos os serviços compartilham o refresh do `identity`
  /// (ADR-013).
  Future<AuthTokens> refreshSession(String refreshToken) async {
    final stored = await _tokenStorage.readSession();
    final tenantId = stored?.tenantId ?? state.tenantId;
    if (tenantId == null) {
      throw StateError('refreshSession chamado sem tenantId conhecido');
    }
    final session = await _authRepository.refresh(
      refreshToken: refreshToken,
      tenantId: tenantId,
    );
    await _applySession(session);
    return AuthTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );
  }

  /// Aplica o resultado de `PUT /v1/me/consents`: o access token novo (com as
  /// finalidades atualizadas nas claims, para os outros serviços enxergarem a
  /// mudança já) e se o gate de consentimento ainda vale.
  Future<void> applyConsentResult({
    required String? accessToken,
    required bool needsConsent,
  }) async {
    final stored = await _tokenStorage.readSession();
    if (stored != null && accessToken != null && accessToken.isNotEmpty) {
      await _tokenStorage.save(
        AuthTokens(
          accessToken: accessToken,
          refreshToken: stored.tokens.refreshToken,
        ),
      );
    }
    if (state.isAuthenticated) {
      state = state.copyWith(consentPending: needsConsent);
    }
  }

  /// Fim da exclusão de conta (ADR-008 §2): os tokens já foram revogados pelo
  /// servidor, então só limpamos a sessão local — sem chamar logout.
  Future<void> completeAccountDeletion() async {
    await _tokenStorage.clear();
    state = const AuthState.unauthenticated();
  }

  Future<void> _applySession(AuthSession session) async {
    await _tokenStorage.saveSession(
      StoredSession(
        tokens: AuthTokens(
          accessToken: session.accessToken,
          refreshToken: session.refreshToken,
        ),
        tenantId: session.tenantId,
        userId: session.userId,
        roles: session.roles,
      ),
    );
    final previousContext = state.activeContext;
    state = AuthState.authenticated(
      roles: session.userRoles,
      tenantId: session.tenantId,
      userId: session.userId,
      activeContext: previousContext,
      isOwner: session.roles.contains('owner'),
      consentPending: session.needsConsent,
    );
  }

  Dio _rawIdentityDio() {
    final dio = Dio(BaseOptions(baseUrl: AppConfig.identityBaseUrl))
      ..interceptors.add(ErrorMappingInterceptor());
    if (_injectedHttpAdapter != null) {
      dio.httpClientAdapter = _injectedHttpAdapter;
    }
    return dio;
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
