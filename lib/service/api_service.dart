import 'package:dio/dio.dart';

class ApiService {
  final Dio _dio;

  ApiService._internal(this._dio);

  factory ApiService(String baseUrl) {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(milliseconds: 15000),
      receiveTimeout: const Duration(milliseconds: 15000),
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

}
