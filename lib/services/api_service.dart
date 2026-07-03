import 'dart:convert';

import 'package:http/http.dart' as http;

// 10.0.2.2 = host PC localhost as seen from Android emulator
// Switch back to http://192.168.1.10:3000 when running on the real phone
const String kApiBaseUrl = 'http://10.0.2.2:3000';

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

  /// Mechanic login → only needs password (shared garage password).
  /// Owner login   → needs username + password, hits /owner-login.
  Future<dynamic> login(String username, String password) async {
    final isMechanic = username.trim().isEmpty;
    final path = isMechanic ? '/api/auth/login' : '/api/auth/owner-login';
    final uri  = Uri.parse('$kApiBaseUrl$path');

    final body = isMechanic
        ? jsonEncode({'password': password})
        : jsonEncode({'username': username.trim(), 'password': password});

    final response = await http.post(
      uri,
      headers: _createHeaders(withAuth: false),
      body: body,
    );

    final decoded = await _decodeResponse(response);
    if (decoded is Map<String, dynamic>) {
      _jwtToken = decoded['token'] ?? decoded['access_token']?.toString();
    }

    return decoded;
  }

  /// Converts a human-readable service name to the backend's snake_case enum value.
  static String _toServiceTypeEnum(String service) {
    switch (service.toLowerCase().trim()) {
      case 'wheel alignment':  return 'wheel_alignment';
      case 'wheel balancing':  return 'wheel_balancing';
      case 'tyre change':      return 'tyre_change';
      case 'water wash':       return 'water_wash';
      case 'full service':     return 'full_service';
      case 'car wash':         return 'car_wash';
      default:                 return 'other';
    }
  }

  /// Converts UI source label to backend enum value.
  static String _toSourceEnum(String source) {
    return source.toLowerCase().contains('whatsapp') ? 'whatsapp' : 'walkin';
  }

  /// Creates a job using the backend's 3-step relational flow:
  /// 1. Look up customer by phone — create if not found
  /// 2. Look up vehicle by number — create if not found (409 = already exists, fetch it)
  /// 3. Create job with customer_id + vehicle_id + service_type enum
  Future<dynamic> createJob(
    String vehicleReg,
    String customerName,
    String phone,
    List<String> services,
    String notes,
    String source,
  ) async {
    // Step 1 — look up customer by phone
    final lookupUri = Uri.parse('$kApiBaseUrl/api/customers/lookup/${Uri.encodeComponent(phone)}');
    final lookupResp = await http.get(lookupUri, headers: _createHeaders());
    final lookupData = await _decodeResponse(lookupResp);

    dynamic customerId = lookupData['data']?['id'];

    if (customerId == null) {
      // New customer — create them
      final createCustUri = Uri.parse('$kApiBaseUrl/api/customers');
      final createCustResp = await http.post(
        createCustUri,
        headers: _createHeaders(),
        body: jsonEncode({'name': customerName, 'phone': phone}),
      );
      final custData = await _decodeResponse(createCustResp);
      customerId = custData['data']?['id'];
    }

    // Step 2 — create vehicle (409 = already registered, look it up)
    final vehicleUri = Uri.parse('$kApiBaseUrl/api/vehicles');
    final vehicleResp = await http.post(
      vehicleUri,
      headers: _createHeaders(),
      body: jsonEncode({'customer_id': customerId, 'vehicle_number': vehicleReg}),
    );

    dynamic vehicleId;
    if (vehicleResp.statusCode == 409) {
      // Vehicle already exists — fetch it by vehicle_number
      final byNumUri = Uri.parse('$kApiBaseUrl/api/vehicles/number/${Uri.encodeComponent(vehicleReg)}');
      final byNumResp = await http.get(byNumUri, headers: _createHeaders());
      final byNumData = await _decodeResponse(byNumResp);
      vehicleId = byNumData['data']?['id'];
    } else {
      final vehicleData = await _decodeResponse(vehicleResp);
      vehicleId = vehicleData['data']?['id'];
    }

    // Step 3 — create job (backend takes single service_type enum)
    final serviceType = _toServiceTypeEnum(services.isNotEmpty ? services.first : 'other');
    final jobUri = Uri.parse('$kApiBaseUrl/api/jobs');
    final jobResp = await http.post(
      jobUri,
      headers: _createHeaders(),
      body: jsonEncode({
        'customer_id': customerId,
        'vehicle_id': vehicleId,
        'service_type': serviceType,
        'notes': notes,
        'source': _toSourceEnum(source),
      }),
    );

    return _decodeResponse(jobResp);
  }

  Future<dynamic> getTodayJobs() async {
    // Pass today's date in IST so the backend filters server-side
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final uri = Uri.parse('$kApiBaseUrl/api/jobs?date=$dateStr');
    final response = await http.get(uri, headers: _createHeaders());
    final decoded = await _decodeResponse(response);

    if (decoded is Map) {
      return decoded['data'] ?? decoded['jobs'] ?? [];
    }
    return decoded ?? [];
  }

  /// [currentStatus] is the job's current status string from the backend.
  /// This maps it to the correct route:
  ///   pending      → PATCH /api/jobs/:id/start
  ///   in_progress  → PATCH /api/jobs/:id/complete
  ///   anything else (e.g. cancel from UI) → PATCH /api/jobs/:id/cancel
  Future<dynamic> updateJobStatus(String jobId, {String currentStatus = 'pending'}) async {
    final s = currentStatus.toLowerCase();
    final String action;
    if (s.contains('pending')) {
      action = 'start';
    } else if (s.contains('progress') || s.contains('in_progress')) {
      action = 'complete';
    } else {
      action = 'cancel';
    }

    final uri = Uri.parse('$kApiBaseUrl/api/jobs/$jobId/$action');
    final response = await http.patch(uri, headers: _createHeaders());
    return _decodeResponse(response);
  }

  Future<dynamic> cancelJob(String jobId) async {
    final uri = Uri.parse('$kApiBaseUrl/api/jobs/$jobId/cancel');
    final response = await http.patch(uri, headers: _createHeaders());
    return _decodeResponse(response);
  }

  Future<dynamic> getJob(String jobId) async {
    final uri = Uri.parse('$kApiBaseUrl/api/jobs/$jobId');
    final response = await http.get(uri, headers: _createHeaders());
    return _decodeResponse(response);
  }

  Future<dynamic> createCustomer(String name, String phone) async {
    final uri = Uri.parse('$kApiBaseUrl/api/customers');
    final response = await http.post(
      uri,
      headers: _createHeaders(),
      body: jsonEncode({'name': name, 'phone': phone}),
    );
    return _decodeResponse(response);
  }

  Future<dynamic> lookupCustomerByPhone(String phone) async {
    final uri = Uri.parse(
      '$kApiBaseUrl/api/customers/lookup/${Uri.encodeComponent(phone)}',
    );
    final response = await http.get(uri, headers: _createHeaders());
    return _decodeResponse(response);
  }

  Future<dynamic> searchCustomers(String query) async {
    final uri = Uri.parse(
      '$kApiBaseUrl/api/customers/search?q=${Uri.encodeComponent(query)}',
    );
    final response = await http.get(uri, headers: _createHeaders());
    final decoded = await _decodeResponse(response);
    if (decoded is Map<String, dynamic>) {
      return decoded['data'] ?? [];
    }
    return decoded;
  }

  Future<dynamic> getCustomerHistory(String phone) async {
    // Step 1 — look up customer by phone to get their UUID
    final lookupUri = Uri.parse(
      '$kApiBaseUrl/api/customers/lookup/${Uri.encodeComponent(phone)}',
    );
    final lookupResp = await http.get(lookupUri, headers: _createHeaders());
    final lookupData = await _decodeResponse(lookupResp);
    final customerId = lookupData['data']?['id']?.toString();

    if (customerId == null) return [];

    // Step 2 — fetch job history by customer UUID
    final historyUri = Uri.parse('$kApiBaseUrl/api/customers/$customerId/jobs');
    final historyResp = await http.get(historyUri, headers: _createHeaders());
    final historyData = await _decodeResponse(historyResp);
    if (historyData is Map<String, dynamic>) {
      return historyData['data'] ?? [];
    }
    return historyData;
  }

  /// [labourCharge] and [partsCharge] are entered by mechanic.
  /// Backend calculates GST + total. Frontend also shows the preview.
  Future<dynamic> generateBill(
    String jobId, {
    double labourCharge = 0,
    double partsCharge = 0,
    double discount = 0,
    String? notes,
  }) async {
    final uri = Uri.parse('$kApiBaseUrl/api/invoices');
    final response = await http.post(
      uri,
      headers: _createHeaders(),
      body: jsonEncode({
        'job_card_id': jobId,
        'labour_charge': labourCharge,
        'parts_charge': partsCharge,
        'discount': discount,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      }),
    );
    return _decodeResponse(response);
  }

  Future<dynamic> getBill(String jobId) async {
    final uri = Uri.parse('$kApiBaseUrl/api/invoices/job/$jobId');
    final response = await http.get(uri, headers: _createHeaders());
    return _decodeResponse(response);
  }

  Future<dynamic> updateInvoice(
    String invoiceId, {
    double labourCharge = 0,
    double partsCharge = 0,
    double discount = 0,
  }) async {
    final uri = Uri.parse('$kApiBaseUrl/api/invoices/$invoiceId');
    final response = await http.put(
      uri,
      headers: _createHeaders(),
      body: jsonEncode({
        'labour_charge': labourCharge,
        'parts_charge':  partsCharge,
        'gst_percent':   18,
        'discount':      discount,
      }),
    );
    return _decodeResponse(response);
  }

  Future<dynamic> markInvoiceAsPaid(String invoiceId, String paymentMethod) async {
    final uri = Uri.parse('$kApiBaseUrl/api/invoices/$invoiceId/pay');
    final response = await http.patch(
      uri,
      headers: _createHeaders(),
      body: jsonEncode({'payment_method': paymentMethod}),
    );
    return _decodeResponse(response);
  }

  Future<dynamic> sendInvoiceWhatsApp(String invoiceId) async {
    final uri = Uri.parse('$kApiBaseUrl/api/invoices/$invoiceId/send');
    final response = await http.patch(uri, headers: _createHeaders());
    return _decodeResponse(response);
  }

  Future<dynamic> completeJob(String jobId) async {
    final uri = Uri.parse('$kApiBaseUrl/api/jobs/$jobId/complete');
    final response = await http.patch(uri, headers: _createHeaders());
    return _decodeResponse(response);
  }

  // ── Wheel Balancing ──────────────────────────────────────────────────────

  Future<dynamic> saveBalancing({
    required String jobCardId,
    double? flWeight,
    double? frWeight,
    double? rlWeight,
    double? rrWeight,
    String? remarks,
    String roundType = 'before',
  }) async {
    final uri = Uri.parse('$kApiBaseUrl/api/balancing');
    final response = await http.post(
      uri,
      headers: _createHeaders(),
      body: jsonEncode({
        'job_card_id': jobCardId,
        if (flWeight != null) 'fl_weight': flWeight,
        if (frWeight != null) 'fr_weight': frWeight,
        if (rlWeight != null) 'rl_weight': rlWeight,
        if (rrWeight != null) 'rr_weight': rrWeight,
        if (remarks != null && remarks.isNotEmpty) 'remarks': remarks,
        'round_type': roundType,
      }),
    );
    return _decodeResponse(response);
  }

  Future<dynamic> getBalancingByJob(String jobId) async {
    final uri = Uri.parse('$kApiBaseUrl/api/balancing/job/$jobId');
    final response = await http.get(uri, headers: _createHeaders());
    return _decodeResponse(response);
  }

  // ── Wheel Alignment ──────────────────────────────────────────────────────

  Future<dynamic> saveAlignment({
    required String jobCardId,
    String? alignmentReport,
    String? remarks,
  }) async {
    final uri = Uri.parse('$kApiBaseUrl/api/alignment');
    final response = await http.post(
      uri,
      headers: _createHeaders(),
      body: jsonEncode({
        'job_card_id': jobCardId,
        if (alignmentReport != null && alignmentReport.isNotEmpty) 'alignment_report': alignmentReport,
        if (remarks != null && remarks.isNotEmpty) 'remarks': remarks,
      }),
    );
    return _decodeResponse(response);
  }

  Future<dynamic> getAlignmentByJob(String jobId) async {
    final uri = Uri.parse('$kApiBaseUrl/api/alignment/job/$jobId');
    final response = await http.get(uri, headers: _createHeaders());
    return _decodeResponse(response);
  }

  // ── Service Details (car wash, full service, etc.) ───────────────────────

  Future<dynamic> saveServiceDetail({
    required String jobCardId,
    required String serviceType,
    String? remarks,
    String? partsUsed,
  }) async {
    final uri = Uri.parse('$kApiBaseUrl/api/service-details');
    final response = await http.post(
      uri,
      headers: _createHeaders(),
      body: jsonEncode({
        'job_card_id': jobCardId,
        'service_type': serviceType,
        if (remarks != null && remarks.isNotEmpty) 'remarks': remarks,
        if (partsUsed != null && partsUsed.isNotEmpty) 'parts_used': partsUsed,
      }),
    );
    return _decodeResponse(response);
  }

  Future<dynamic> getServiceDetailsByJob(String jobId) async {
    final uri = Uri.parse('$kApiBaseUrl/api/service-details/job/$jobId');
    final response = await http.get(uri, headers: _createHeaders());
    return _decodeResponse(response);
  }

  // ── Reports ──────────────────────────────────────────────────────────────

  Future<dynamic> getAdminSummary() async {
    final uri = Uri.parse('$kApiBaseUrl/api/reports/summary');
    final response = await http.get(uri, headers: _createHeaders());
    return _decodeResponse(response);
  }

  Future<dynamic> getDailyReport(String range) async {
    final uri = Uri.parse('$kApiBaseUrl/api/reports/daily?range=$range');
    final response = await http.get(uri, headers: _createHeaders());
    return _decodeResponse(response);
  }

  Future<dynamic> getServiceAnalysis(String range) async {
    final uri = Uri.parse('$kApiBaseUrl/api/reports/service-analysis?range=$range');
    final response = await http.get(uri, headers: _createHeaders());
    return _decodeResponse(response);
  }

  Future<dynamic> getUnpaidInvoices() async {
    final uri = Uri.parse('$kApiBaseUrl/api/reports/unpaid');
    final response = await http.get(uri, headers: _createHeaders());
    return _decodeResponse(response);
  }

  Future<dynamic> getRevenueTrend() async {
    final uri = Uri.parse('$kApiBaseUrl/api/reports/revenue-trend');
    final response = await http.get(uri, headers: _createHeaders());
    return _decodeResponse(response);
  }

  // ── Appointments (from WhatsApp bot) ────────────────────────────────────

  Future<dynamic> getAppointments({String? status}) async {
    final params = <String, String>{
      if (status != null && status.isNotEmpty) 'status': status,
    };
    final uri = Uri.parse('$kApiBaseUrl/api/appointments').replace(queryParameters: params.isEmpty ? null : params);
    final response = await http.get(uri, headers: _createHeaders());
    final decoded = await _decodeResponse(response);
    if (decoded is Map<String, dynamic>) return decoded['data'] ?? [];
    return decoded ?? [];
  }

  Future<dynamic> acceptAppointment(String id) async {
    final uri = Uri.parse('$kApiBaseUrl/api/appointments/$id/accept');
    final response = await http.patch(uri, headers: _createHeaders());
    return _decodeResponse(response);
  }

  Future<dynamic> rejectAppointment(String id, {String? reason}) async {
    final uri = Uri.parse('$kApiBaseUrl/api/appointments/$id/reject');
    final response = await http.patch(
      uri,
      headers: _createHeaders(),
      body: jsonEncode({if (reason != null && reason.isNotEmpty) 'reason': reason}),
    );
    return _decodeResponse(response);
  }

  // ── Settings ─────────────────────────────────────────────────────────────

  Future<dynamic> getSettings() async {
    final uri = Uri.parse('$kApiBaseUrl/api/settings');
    final response = await http.get(uri, headers: _createHeaders());
    return _decodeResponse(response);
  }

  Future<dynamic> updateSettings({
    required String garageName,
    required String openTime,
    required String closeTime,
    required String workingDays,
    required double gstPercent,
  }) async {
    final uri = Uri.parse('$kApiBaseUrl/api/settings');
    final response = await http.put(
      uri,
      headers: _createHeaders(),
      body: jsonEncode({
        'garage_name':  garageName,
        'open_time':    openTime,
        'close_time':   closeTime,
        'working_days': workingDays,
        'gst_percent':  gstPercent,
      }),
    );
    return _decodeResponse(response);
  }

  Future<dynamic> updateGaragePassword({
    required String newPassword,
    required String confirmPassword,
  }) async {
    final uri = Uri.parse('$kApiBaseUrl/api/settings/garage-password');
    final response = await http.patch(
      uri,
      headers: _createHeaders(),
      body: jsonEncode({
        'new_password':     newPassword,
        'confirm_password': confirmPassword,
      }),
    );
    return _decodeResponse(response);
  }

  Future<dynamic> updateOwnerCredentials({
    required String username,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final uri = Uri.parse('$kApiBaseUrl/api/settings/owner-credentials');
    final response = await http.patch(
      uri,
      headers: _createHeaders(),
      body: jsonEncode({
        'username':         username,
        'new_password':     newPassword,
        'confirm_password': confirmPassword,
      }),
    );
    return _decodeResponse(response);
  }

  // ── Inventory ─────────────────────────────────────────────────────────────

  Future<dynamic> getInventory({String? category}) async {
    final params = <String, String>{
      if (category != null && category.isNotEmpty) 'category': category,
    };
    final uri = Uri.parse('$kApiBaseUrl/api/inventory').replace(queryParameters: params.isEmpty ? null : params);
    final response = await http.get(uri, headers: _createHeaders());
    final decoded = await _decodeResponse(response);
    if (decoded is Map<String, dynamic>) return decoded['data'] ?? [];
    return decoded ?? [];
  }

  Future<dynamic> getLowStockItems() async {
    final uri = Uri.parse('$kApiBaseUrl/api/inventory/low-stock');
    final response = await http.get(uri, headers: _createHeaders());
    final decoded = await _decodeResponse(response);
    if (decoded is Map<String, dynamic>) return decoded['data'] ?? [];
    return decoded ?? [];
  }

  Future<dynamic> addInventoryItem({
    required String name,
    required String category,
    int quantity = 0,
    String unit = 'pcs',
    int minStock = 5,
  }) async {
    final uri = Uri.parse('$kApiBaseUrl/api/inventory');
    final response = await http.post(
      uri,
      headers: _createHeaders(),
      body: jsonEncode({'name': name, 'category': category, 'quantity': quantity, 'unit': unit, 'min_stock': minStock}),
    );
    return _decodeResponse(response);
  }

  Future<dynamic> updateInventoryItem(
    String id, {
    required String name,
    required String category,
    int quantity = 0,
    String unit = 'pcs',
    int minStock = 5,
  }) async {
    final uri = Uri.parse('$kApiBaseUrl/api/inventory/$id');
    final response = await http.put(
      uri,
      headers: _createHeaders(),
      body: jsonEncode({'name': name, 'category': category, 'quantity': quantity, 'unit': unit, 'min_stock': minStock}),
    );
    return _decodeResponse(response);
  }

  Future<dynamic> deleteInventoryItem(String id) async {
    final uri = Uri.parse('$kApiBaseUrl/api/inventory/$id');
    final response = await http.delete(uri, headers: _createHeaders());
    return _decodeResponse(response);
  }

  // ── Tyre Stock ────────────────────────────────────────────────────────────

  Future<dynamic> getTyres({String? brand, String? size}) async {
    final params = <String, String>{
      if (brand != null && brand.isNotEmpty) 'brand': brand,
      if (size  != null && size.isNotEmpty)  'size':  size,
    };
    final uri = Uri.parse('$kApiBaseUrl/api/tyres').replace(queryParameters: params.isEmpty ? null : params);
    final response = await http.get(uri, headers: _createHeaders());
    final decoded = await _decodeResponse(response);
    if (decoded is Map<String, dynamic>) return decoded['data'] ?? [];
    return decoded ?? [];
  }

  Future<dynamic> addTyre({
    required String brand,
    required String size,
    String? model,
    String? vehicleType,
    int quantity = 0,
    double? price,
    String? offer,
  }) async {
    final uri = Uri.parse('$kApiBaseUrl/api/tyres');
    final response = await http.post(
      uri,
      headers: _createHeaders(),
      body: jsonEncode({
        'brand':    brand,
        'size':     size,
        if (model       != null && model.isNotEmpty)       'model':        model,
        if (vehicleType != null && vehicleType.isNotEmpty) 'vehicle_type': vehicleType,
        'quantity': quantity,
        if (price != null) 'price': price,
        if (offer != null && offer.isNotEmpty) 'offer': offer,
      }),
    );
    return _decodeResponse(response);
  }

  Future<dynamic> updateTyre(
    String tyreId, {
    required String brand,
    required String size,
    String? model,
    String? vehicleType,
    int quantity = 0,
    double? price,
    String? offer,
  }) async {
    final uri = Uri.parse('$kApiBaseUrl/api/tyres/$tyreId');
    final response = await http.put(
      uri,
      headers: _createHeaders(),
      body: jsonEncode({
        'brand':    brand,
        'size':     size,
        if (model       != null) 'model':        model,
        if (vehicleType != null) 'vehicle_type': vehicleType,
        'quantity': quantity,
        if (price != null) 'price': price,
        if (offer != null) 'offer': offer,
      }),
    );
    return _decodeResponse(response);
  }

  Future<dynamic> deleteTyre(String tyreId) async {
    final uri = Uri.parse('$kApiBaseUrl/api/tyres/$tyreId');
    final response = await http.delete(uri, headers: _createHeaders());
    return _decodeResponse(response);
  }

  // ── Tyre Change ───────────────────────────────────────────────────────────

  Future<dynamic> saveTyreChange({
    required String jobCardId,
    required String tyreId,
    required int quantity,
    String? remarks,
  }) async {
    final uri = Uri.parse('$kApiBaseUrl/api/service-details/tyre-change');
    final response = await http.post(
      uri,
      headers: _createHeaders(),
      body: jsonEncode({
        'job_card_id': jobCardId,
        'tyre_id':     tyreId,
        'quantity':    quantity,
        if (remarks != null && remarks.isNotEmpty) 'remarks': remarks,
      }),
    );
    return _decodeResponse(response);
  }

  Future<dynamic> getTyreChangeByJob(String jobId) async {
    final uri = Uri.parse('$kApiBaseUrl/api/service-details/tyre-change/job/$jobId');
    final response = await http.get(uri, headers: _createHeaders());
    final decoded = await _decodeResponse(response);
    if (decoded is Map<String, dynamic>) return decoded['data'] ?? [];
    return decoded ?? [];
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
