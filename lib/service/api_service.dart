import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'models/store_zone.dart';

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

  Future<Response> driverLogin(String mobile) async {
    final data = {'mobile': mobile};
    return await _dio.post('/api/twc_driver/login', data: data);
  }

  Future<Response> driverAttendance({
    required String mobile,
    required double lat,
    required double long,
  }) async {
    final data = {
      'mobile': mobile,
      'lat': lat,
      'long': long,
    };
    return await _dio.post('/api/twc_driver/check-in-out', data: data);
  }

  /// 🔄 Send a batch of location records to the n8n webhook
  Future<Response> sendLocationBatch(List<Map<String, dynamic>> batch) async {
    return await _dio.post('/api/twc_driver/tracking', data: batch);
  }

  // Optionally call this once after login so every call carries cookie
  void setCookieHeader(String cookie) {
    _dio.options.headers['Cookie'] = cookie; // e.g., "session_id=....; frontend_lang=en_US"
  }

  Future<List<StoreZone>> fetchStores() async {
    final resp = await _dio.get('/api/twc_driver/stores');
    if (resp.statusCode != 200) {
      throw DioException(
        requestOptions: resp.requestOptions,
        response: resp,
        message: 'Failed to fetch stores',
        type: DioExceptionType.badResponse,
      );
    }
    final data = resp.data;
    final list = (data is Map && data['data'] is List) ? (data['data'] as List) : <dynamic>[];
    return list.map((e) => StoreZone.fromJson(e as Map<String, dynamic>)).toList();
  }
}
