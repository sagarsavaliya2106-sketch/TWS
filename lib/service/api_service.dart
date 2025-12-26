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

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        debugPrint('🌐 [API Request]');
        debugPrint('➡️ URL: ${options.uri}');
        debugPrint('🟢 Method: ${options.method}');
        if (options.data != null) debugPrint('📦 Body: ${options.data}');
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
        if (e.response != null) debugPrint('📦 Response: ${e.response?.data}');
        return handler.next(e);
      },
    ));

    return ApiService._internal(dio);
  }

  /// Step 1 — send OTP
  Future<Response> sendOtp(String mobileNo) async {
    final data = {'mobile_no': mobileNo};
    return await _dio.post('/api/twc_driver/send_otp', data: data);
  }

  /// Step 2 — verify OTP & login
  Future<Response> verifyOtp(String mobileNo, String otpCode) async {
    final data = {
      'mobile_no': mobileNo,
      'otp_code': otpCode,
    };
    return await _dio.post('/api/twc_driver/login', data: data);
  }

  Future<Response> driverAttendance({
    required String mobile,
    required double lat,
    required double long,
  }) async {
    final data = {'mobile': mobile, 'lat': lat, 'long': long};
    return await _dio.post('/api/twc_driver/check-in-out', data: data);
  }


  /// Toggle driver duty (on/off)
  /// API: POST /api/twc_driver/duty
  /// Body: { "mobile_no": "...", "action": "on" | "off" }
  /// Response (JSON-RPC style): { "result": { "status": "...", "message": "...", ... } }
  Future<Map<String, dynamic>> driverDuty({
    required String mobileNo,
    required String action, // "on" or "off"
  }) async {
    final resp = await _dio.post(
      '/api/twc_driver/duty',
      data: {
        'mobile_no': mobileNo,
        'action': action,
      },
    );

    if (resp.statusCode == 200 && resp.data is Map) {
      final result = (resp.data as Map)['result'];
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
    }
    throw Exception('Failed to toggle duty');
  }

  Future<Response> sendLocationBatch(List<Map<String, dynamic>> batch) async {
    return await _dio.post('/api/twc_driver/tracking', data: batch);
  }

  Future<List<Map<String, dynamic>>> fetchTrackingLogs(String mobile, {int limit = 10}) async {
    final resp = await _dio.get(
      '/api/twc_driver/tracking',
      queryParameters: {
        'mobile': mobile,
        // 'limit': limit,
      },
    );

    if (resp.statusCode == 200 && resp.data is Map) {
      final data = resp.data['data'];
      if (data is List) {
        return data.map((e) => e as Map<String, dynamic>).toList();
      }
    }
    throw Exception('Failed to fetch tracking logs');
  }

  Future<List<Map<String, dynamic>>> fetchCheckInOutLogs(String mobile, {int limit = 10}) async {
    final resp = await _dio.get(
      '/api/twc_driver/check-in-out',
      queryParameters: {
        'mobile': mobile,
        // 'limit': limit,
      },
    );

    if (resp.statusCode == 200 && resp.data is Map) {
      final data = resp.data['data'];
      if (data is List) {
        return data.map((e) => e as Map<String, dynamic>).toList();
      }
    }
    throw Exception('Failed to fetch check-in/out logs');
  }

  void setCookieHeader(String cookie) {
    _dio.options.headers['Cookie'] = cookie;
  }
}
