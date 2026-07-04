import 'package:dio/dio.dart';

import 'api_exception.dart';

/// Converte respostas de erro HTTP no envelope `{ "code": "...", "params":
/// {...} }` (`backend/README.md`, ADR-011 §3) em [ApiException], para a
/// camada de apresentação traduzir sem conhecer o formato HTTP/Dio.
class ErrorMappingInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    handler.next(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: _toApiException(err),
      ),
    );
  }

  ApiException _toApiException(DioException err) {
    final data = err.response?.data;
    if (data is Map<String, dynamic> && data['code'] is String) {
      final rawParams = data['params'];
      return ApiException(
        code: data['code'] as String,
        params: rawParams is Map<String, dynamic> ? rawParams : const {},
        statusCode: err.response?.statusCode,
      );
    }
    return const ApiException.network();
  }
}
