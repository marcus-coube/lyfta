/// Exceção que representa o envelope de erro padrão da API
/// (`backend/README.md` / `apierror.go`): `{ "code": "...", "params": {...} }`.
///
/// `code` é estável e nunca é exibido direto ao usuário — a tradução para
/// mensagem i18n acontece na camada de apresentação (ADR-011 §3), com
/// [params] disponível para interpolação (ex.: `field` em `validation_error`).
class ApiException implements Exception {
  const ApiException({
    required this.code,
    this.params = const {},
    this.statusCode,
  });

  /// Erro de rede/timeout — sem resposta do servidor.
  const ApiException.network() : this(code: 'network_error');

  final String code;
  final Map<String, dynamic> params;
  final int? statusCode;

  @override
  String toString() => 'ApiException(code: $code, params: $params)';
}
