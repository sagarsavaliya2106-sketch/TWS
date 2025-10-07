import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class ApiService {
  final Dio _dio;

  ApiService._internal(this._dio);

  factory ApiService(String baseUrl) {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(milliseconds: 15000),
      receiveTimeout: const Duration(milliseconds: 15000),
    ));

    // ✅ Add simple console logger
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        debugPrint('🌐 [API Request]');
        debugPrint('➡️ URL: ${options.uri}');
        debugPrint('🟢 Method: ${options.method}');
        if (options.data != null) {
          debugPrint('📦 Body: ${options.data}');
        }
        return handler.next(options);
      },
      onResponse: (response, handler) {
        debugPrint('✅ [API Response]');
        debugPrint('⬅️ URL: ${response.realUri}');
        debugPrint('📄 Status: ${response.statusCode}');
        debugPrint('📦 Data: ${response.data}');
        return handler.next(response);
      },
      onError: (DioException e, handler) {
        debugPrint('❌ [API Error]');
        debugPrint('⬅️ URL: ${e.requestOptions.uri}');
        debugPrint('📄 Message: ${e.message}');
        if (e.response != null) {
          debugPrint('📦 Response: ${e.response?.data}');
        }
        return handler.next(e);
      },
    ));

    return ApiService._internal(dio);
  }

  Future<Response> login(String mobile) async {
    final data = {'mobile': mobile};
    return await _dio.post('/login', data: data);
  }

  Future<Response> checkIn(String mobile) async {
    final data = {'mobile': mobile};
    return await _dio.post('/check-in', data: data);
  }

  Future<Response> driverLogin(String mobile) async {
    final data = {'mobile': mobile};
    return await _dio.post('/api/twc_driver/login', data: data);
  }

  Future<Response> driverAttendance(String mobile) async {
    final data = {'mobile': mobile};
    return await _dio.post('/api/twc_driver/attendance', data: data);
  }

  /// 🔄 Send a batch of location records to the n8n webhook
  Future<Response> sendLocationBatch(List<Map<String, dynamic>> batch) async {
    return await _dio.post('/api/twc_driver/tracking', data: batch);
  }
}
