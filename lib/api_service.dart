import 'dart:convert';

import 'package:http/http.dart' as http;

const String kApiBaseUrl = 'https://api.example.com';

class ApiService {
  String? _jwtToken;

  String? get jwtToken => _jwtToken;

  Map<String, String> _createHeaders({bool withAuth = true}) {
    final headers = <String, String>{'Content-Type': 'application/json'};

    if (withAuth) {
      if (_jwtToken == null || _jwtToken!.isEmpty) {
        throw StateError(
          'JWT token is not set. Call login() before making authenticated requests.',
        );
      }

      headers['Authorization'] = 'Bearer $_jwtToken';
    }

    return headers;
  }

  Future<dynamic> _decodeResponse(http.Response response) async {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        response.body,
        response.request?.url.toString(),
      );
    }

    if (response.body.isEmpty) {
      return null;
    }

    return jsonDecode(response.body);
  }

  Future<dynamic> login(String username, String password) async {
    final uri = Uri.parse('$kApiBaseUrl/auth/login');
    final response = await http.post(
      uri,
      headers: _createHeaders(withAuth: false),
      body: jsonEncode({'username': username, 'password': password}),
    );

    final decoded = await _decodeResponse(response);
    if (decoded is Map<String, dynamic>) {
      _jwtToken = decoded['token'] ?? decoded['access_token']?.toString();
    }

    return decoded;
  }

  Future<dynamic> createJob(
    String vehicleReg,
    String customerName,
    String phone,
    List<String> services,
    String notes,
    String source,
  ) async {
    final uri = Uri.parse('$kApiBaseUrl/jobs/create');
    final response = await http.post(
      uri,
      headers: _createHeaders(),
      body: jsonEncode({
        'vehicleReg': vehicleReg,
        'customerName': customerName,
        'phone': phone,
        'services': services,
        'notes': notes,
        'source': source,
      }),
    );

    return _decodeResponse(response);
  }

  Future<dynamic> getTodayJobs() async {
    final uri = Uri.parse('$kApiBaseUrl/jobs/today');
    final response = await http.get(uri, headers: _createHeaders());
    return _decodeResponse(response);
  }

  Future<dynamic> updateJobStatus(String jobId) async {
    final uri = Uri.parse('$kApiBaseUrl/jobs/$jobId/status');
    final response = await http.patch(
      uri,
      headers: _createHeaders(),
      body: jsonEncode({}),
    );
    return _decodeResponse(response);
  }

  Future<dynamic> getJob(String jobId) async {
    final uri = Uri.parse('$kApiBaseUrl/jobs/$jobId');
    final response = await http.get(uri, headers: _createHeaders());
    return _decodeResponse(response);
  }

  Future<dynamic> createCustomer(
    String name,
    String phone,
    String vehicleReg,
  ) async {
    final uri = Uri.parse('$kApiBaseUrl/customers/create');
    final response = await http.post(
      uri,
      headers: _createHeaders(),
      body: jsonEncode({
        'name': name,
        'phone': phone,
        'vehicleReg': vehicleReg,
      }),
    );

    return _decodeResponse(response);
  }

  Future<dynamic> searchCustomers(String query) async {
    final uri = Uri.parse(
      '$kApiBaseUrl/customers/search',
    ).replace(queryParameters: {'q': query});
    final response = await http.get(uri, headers: _createHeaders());
    return _decodeResponse(response);
  }

  Future<dynamic> getCustomerHistory(String phone) async {
    final uri = Uri.parse(
      '$kApiBaseUrl/customers/${Uri.encodeComponent(phone)}/history',
    );
    final response = await http.get(uri, headers: _createHeaders());
    return _decodeResponse(response);
  }

  Future<dynamic> generateBill(String jobId) async {
    final uri = Uri.parse('$kApiBaseUrl/billing/generate');
    final response = await http.post(
      uri,
      headers: _createHeaders(),
      body: jsonEncode({'jobId': jobId}),
    );
    return _decodeResponse(response);
  }

  Future<dynamic> getBill(String jobId) async {
    final uri = Uri.parse('$kApiBaseUrl/billing/$jobId');
    final response = await http.get(uri, headers: _createHeaders());
    return _decodeResponse(response);
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String responseBody;
  final String? requestUrl;

  ApiException(this.statusCode, this.responseBody, this.requestUrl);

  @override
  String toString() {
    final urlPart = requestUrl != null ? ' for $requestUrl' : '';
    return 'ApiException: HTTP $statusCode$urlPart - ${responseBody.isEmpty ? 'No response body' : responseBody}';
  }
}
