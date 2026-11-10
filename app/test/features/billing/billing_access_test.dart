import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/auth/auth_controller.dart';
import 'package:lyfta/core/auth/auth_state.dart';
import 'package:lyfta/features/account/data/tenant_repository.dart';
import 'package:lyfta/features/billing/presentation/billing_providers.dart';

class _Auth extends AuthController {
  _Auth(this.roles, {this.isOwner = false});

  final Set<UserRole> roles;
  final bool isOwner;

  @override
  AuthState build() => AuthState.authenticated(
        roles: roles,
        tenantId: 't',
        userId: 'u',
        isOwner: isOwner,
      );
}

class _Tenants extends TenantRepository {
  _Tenants(this.access) : super(Dio());

  final String access;

  @override
  Future<TenantSettings> get() async => TenantSettings(
        id: 't',
        name: 'Org',
        slug: 'org',
        locale: 'pt-BR',
        timezone: 'America/Sao_Paulo',
        coachBillingAccess: access,
      );
}

Future<BillingAccess> _access(
  Set<UserRole> roles, {
  bool isOwner = false,
  String access = 'status_only',
}) async {
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith(() => _Auth(roles, isOwner: isOwner)),
      tenantRepositoryProvider.overrideWithValue(_Tenants(access)),
    ],
  );
  addTearDown(container.dispose);
  container.listen(billingAccessProvider, (_, __) {});
  await container.read(tenantSettingsProvider.future).catchError(
        (_) => const TenantSettings(
          id: '',
          name: '',
          slug: '',
          locale: '',
          timezone: '',
          coachBillingAccess: '',
        ),
      );
  return container.read(billingAccessProvider);
}

void main() {
  test('owner opera tudo, sem depender da configuração', () async {
    final a = await _access({UserRole.coach}, isOwner: true);
    expect(a, BillingAccess.owner);
    expect(a.canOperate, isTrue);
    expect(a.isOwner, isTrue);
  });

  test('coach com own_students opera, mas não é owner', () async {
    final a = await _access({UserRole.coach}, access: 'own_students');
    expect(a, BillingAccess.coachOperator);
    expect(a.canOperate, isTrue);
    expect(a.isOwner, isFalse);
  });

  test('coach com status_only não opera: sem aba nem valores', () async {
    final a = await _access({UserRole.coach});
    expect(a, BillingAccess.statusOnly);
    expect(a.canOperate, isFalse);
  });

  test('aluno não tem acesso ao financeiro da organização', () async {
    final a = await _access({UserRole.student});
    expect(a, BillingAccess.none);
  });
}
