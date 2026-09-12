import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/app_config.dart';

/// Assinatura para obter/renovar o access token usado no handshake — o
/// mesmo par (token atual + refresh) que o `AuthInterceptor` usa nas
/// chamadas REST, mas o WS não tem interceptor: o token vai só uma vez, na
/// query string do `GET /ws?token=` (o handshake de WS do browser não manda
/// header customizado — mesma razão documentada em `internal/http/ws.go`
/// do `comms`).
typedef ReadAccessToken = Future<String?> Function();
typedef RefreshAccessToken = Future<String?> Function();

/// Cliente WebSocket do `comms` (`GET /ws?token=`, P3.2/P3.3) — a única
/// conexão do app para eventos em tempo real, reusada por chat (P3.5 §1) e
/// pela fila de check-ins do coach (P3.5 §3): mora em `core/` porque as duas
/// features precisam da mesma conexão sem importar uma da outra
/// (`docs/guidelines/flutter.md`: "feature não importa outra feature; o que
/// for comum sobe para shared/ ou core/").
///
/// Este serviço **não sabe o que os eventos significam** — entrega JSON cru
/// decodificado (`Map<String, dynamic>`, sempre com um campo `type`); cada
/// feature decide o que fazer com o `type` que lhe interessa. Reconexão com
/// backoff exponencial, mesmo desenho do `SyncWorker` do P1.7 (mas para
/// entrada, não fila de saída).
class CommsSocketService {
  CommsSocketService({
    required ReadAccessToken readAccessToken,
    required RefreshAccessToken refreshAccessToken,
  })  : _readAccessToken = readAccessToken,
        _refreshAccessToken = refreshAccessToken;

  final ReadAccessToken _readAccessToken;
  final RefreshAccessToken _refreshAccessToken;

  static const Duration _maxBackoff = Duration(seconds: 30);

  final _eventsController = StreamController<Map<String, dynamic>>.broadcast();

  /// Emite depois de toda reconexão bem-sucedida que **não** é a primeira —
  /// o gatilho para quem está com uma tela aberta recarregar via REST o que
  /// pode ter perdido durante a queda (Aceite do P3.2).
  final _reconnectedController = StreamController<void>.broadcast();

  Stream<Map<String, dynamic>> get events => _eventsController.stream;
  Stream<void> get onReconnected => _reconnectedController.stream;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retryTimer;
  int _attempt = 0;
  bool _everConnected = false;
  bool _disposed = false;
  bool _connecting = false;

  bool get isConnected => _channel != null;

  Uri _wsUri(String token) {
    final base = Uri.parse(AppConfig.commsBaseUrl);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    return base.replace(
      scheme: scheme,
      path: '/ws',
      queryParameters: {'token': token},
    );
  }

  /// Conecta (ou reconecta) — idempotente: chamar de novo com uma conexão
  /// já aberta ou uma tentativa já em curso não faz nada.
  Future<void> connect() async {
    if (_disposed || _connecting || _channel != null) return;
    _connecting = true;
    try {
      // Depois de várias falhas seguidas, o token pode ter apenas expirado
      // (uma sessão de horas com o app em segundo plano) — força um refresh
      // antes de insistir com o mesmo token velho.
      final forceRefresh = _attempt > 0 && _attempt % 3 == 0;
      final token = forceRefresh
          ? (await _refreshAccessToken() ?? await _readAccessToken())
          : await _readAccessToken();
      if (token == null) return;

      final channel = WebSocketChannel.connect(_wsUri(token));
      await channel.ready;

      _channel = channel;
      final wasReconnect = _everConnected;
      _everConnected = true;
      _attempt = 0;
      _retryTimer?.cancel();

      _subscription = channel.stream.listen(
        _onData,
        onError: (_) => _handleDisconnect(),
        onDone: _handleDisconnect,
        cancelOnError: true,
      );

      if (wasReconnect) _reconnectedController.add(null);
    } catch (_) {
      _channel = null;
      _scheduleRetry();
    } finally {
      _connecting = false;
    }
  }

  void _onData(dynamic raw) {
    if (raw is! String) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _eventsController.add(json);
    } catch (_) {
      // Frame que não decodifica (ex.: pong de controle chegando como frame
      // de dados em alguma implementação) não derruba a conexão.
    }
  }

  void _handleDisconnect() {
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    if (_disposed) return;
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_disposed) return;
    _attempt++;
    final seconds = 1 << _attempt.clamp(1, 6); // 2s..64s, teto em _maxBackoff
    final delay = Duration(seconds: seconds) < _maxBackoff
        ? Duration(seconds: seconds)
        : _maxBackoff;
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () => unawaited(connect()));
  }

  /// Fecha a conexão e para de tentar reconectar — chamado no sign-out
  /// (mesma razão do `WorkoutRepository.clearLocal`: nada de outra sessão
  /// deve continuar chegando depois que o usuário saiu).
  void disconnect() {
    _retryTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _attempt = 0;
    _everConnected = false;
  }

  void dispose() {
    _disposed = true;
    disconnect();
    unawaited(_eventsController.close());
    unawaited(_reconnectedController.close());
  }
}
