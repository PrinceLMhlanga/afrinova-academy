import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

class PayNowService {
  final SupabaseClient _client = Supabase.instance.client;
  String? _integrationId;
  String? _integrationKey;
  
  // Your Vercel API URL
  // Change this line in paynow_service.dart
static const String _vercelApiUrl = 'https://www.afrinova-academy.com/api/paynow';

  Future<void> _loadSettings() async {
    if (_integrationId != null) return;

    final response = await _client
        .from('platform_settings')
        .select('key, value')
        .or('key.eq.paynow_integration_id,key.eq.paynow_integration_key');

    for (final row in response) {
      if (row['key'] == 'paynow_integration_id') {
        _integrationId = row['value'] as String;
      }
      if (row['key'] == 'paynow_integration_key') {
        _integrationKey = row['value'] as String;
      }
    }
  }

  String _generateHash(Map<String, String> items) {
    final concat = items.entries
        .where((e) => e.key.toLowerCase() != 'hash')
        .map((e) => e.value)
        .join('');

    final stringToHash = '$concat$_integrationKey';
    final bytes = utf8.encode(stringToHash);
    final digest = sha512.convert(bytes);
    return digest.toString().toUpperCase();
  }

  // Keep this method - it's what PaymentScreen calls
  Future<PayNowResponse> initiateMobilePayment({
    required String reference,
    required double amount,
    required String mobileNumber,
    String email = '',
    String carrier = 'ecocash',
  }) async {
    try {
      await _loadSettings();

      if ((_integrationId ?? '').isEmpty || (_integrationKey ?? '').isEmpty) {
        return PayNowResponse(success: false, error: 'PayNow credentials are not configured.');
      }

      // Use Vercel API for web, direct for mobile
      if (kIsWeb) {
        return _initiateViaVercel(reference, amount, mobileNumber, email);
      } else {
        return _initiateDirect(reference, amount, mobileNumber, email, carrier);
      }
    } catch (e) {
      debugPrint('PayNow error: $e');
      return PayNowResponse(success: false, error: e.toString());
    }
  }

  Future<PayNowResponse> _initiateViaVercel(
  String reference,
  double amount,
  String mobileNumber,
  String email,
) async {
  try {
    // Use the constant instead of hardcoded URL
    final body = jsonEncode({
      'reference': reference,
      'amount': amount,
      'mobileNumber': mobileNumber,
      'email': email,
    });

    debugPrint('🔵 Attempting Vercel API call...');
    debugPrint('🔵 URL: $_vercelApiUrl');
    debugPrint('🔵 Body: $body');

    final response = await http.post(
      Uri.parse(_vercelApiUrl),  // ✅ Use the constant
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    debugPrint('🔵 Status code: ${response.statusCode}');
    debugPrint('🔵 Response body: ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return PayNowResponse(
        success: data['success'] ?? false,
        reference: data['reference'],
        pollUrl: data['pollUrl'],
        error: data['error'],
      );
    } else {
      debugPrint('🔴 Non-200 status: ${response.statusCode}');
      return PayNowResponse(
        success: false, 
        error: 'Server error: ${response.statusCode}'
      );
    }
  } catch (e, stackTrace) {
    debugPrint('🔴 EXCEPTION: ${e.runtimeType}');
    debugPrint('🔴 ERROR: $e');
    
    if (e.toString().contains('SocketException')) {
      return PayNowResponse(success: false, error: 'Network error: Cannot reach server');
    }
    if (e.toString().contains('HandshakeException')) {
      return PayNowResponse(success: false, error: 'SSL/HTTPS error');
    }
    if (e.toString().contains('XmlHttpRequest') || e.toString().contains('Failed to fetch')) {
      return PayNowResponse(success: false, error: 'CORS or browser security error');
    }
    
    return PayNowResponse(success: false, error: 'Failed: ${e.toString()}');
  }
}
  Future<PayNowResponse> _initiateDirect(
    String reference,
    double amount,
    String mobileNumber,
    String email,
    String carrier,
  ) async {
    final amountStr = amount.toStringAsFixed(2);
    final autoEmail = email.trim().isNotEmpty ? email.trim() : '$mobileNumber@mobile.paynow.co.zw';

    final items = <String, String>{
      'id': _integrationId ?? '',
      'reference': reference,
      'amount': amountStr,
      'authemail': autoEmail,
      'additionalinfo': '',
      'returnurl': 'https://afrinova.academy/payment/complete',
      'resulturl': 'https://rwheufzhixqqifoleltu.supabase.co/functions/v1/paynow-webhook',
      'status': 'Message',
      'phone': mobileNumber.trim(),
      'method': carrier,
    };

    final hash = _generateHash(items);
    items['hash'] = hash;

    final postData = items.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');

    final response = await http
        .post(
          Uri.parse('https://www.paynow.co.zw/interface/remotetransaction'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: postData,
        )
        .timeout(const Duration(seconds: 30));

    return _parseResponse(response.body, reference);
  }

  PayNowResponse _parseResponse(String body, String reference) {
    final result = PayNowResponse(success: false, reference: reference);
    
    final lines = body.split(RegExp(r'[\r\n&]'));
    for (final line in lines) {
      if (line.isEmpty) continue;
      final separatorIndex = line.indexOf('=');
      if (separatorIndex < 0) continue;

      final key = line.substring(0, separatorIndex).toLowerCase();
      final value = Uri.decodeComponent(line.substring(separatorIndex + 1));

      if (key == 'pollurl') result.pollUrl = value;
      if (key == 'status') result.success = value.toLowerCase() == 'ok';
      if (key == 'error') result.error = value;
    }

    return result;
  }

  Future<PayNowStatusResponse> pollTransaction(String pollUrl) async {
    try {
      if (pollUrl.isEmpty) {
        return PayNowStatusResponse(paid: false, status: 'Error', error: 'Empty poll URL');
      }

      final response = await http
          .post(Uri.parse(pollUrl), body: '')
          .timeout(const Duration(seconds: 20));

      return _parseStatusResponse(response.body);
    } catch (e) {
      debugPrint('Poll error: $e');
      return PayNowStatusResponse(paid: false, status: 'Error', error: e.toString());
    }
  }

  Future<String> createPendingPayment({
    required String studentId,
    required String teacherId,
    required double amount,
    String? enrollmentId,
    String? pricingPlanId, 
  }) async {
    final reference = 'AFRINOVA-${DateTime.now().millisecondsSinceEpoch}';

    await _client.from('payments').insert({
      'student_id': studentId,
      'teacher_id': teacherId,
      'amount': amount,
      'gateway_reference': reference,
      'status': 'pending',
      'payment_method': 'ecocash',
      'enrollment_id': enrollmentId,
      'pricing_plan_id': pricingPlanId,
      'created_at': DateTime.now().toIso8601String(),
    });

    debugPrint('Created new pending payment: $reference');
    return reference;
  }

  PayNowStatusResponse _parseStatusResponse(String body) {
    final result = PayNowStatusResponse(paid: false, status: 'pending');
    final pairs = body.split('&');
    final dict = <String, String>{};

    for (final pair in pairs) {
      if (pair.isEmpty) continue;
      final separatorIndex = pair.indexOf('=');
      if (separatorIndex < 0) continue;

      final key = pair.substring(0, separatorIndex).toLowerCase();
      final value = pair.substring(separatorIndex + 1);
      dict[key] = Uri.decodeComponent(value);
    }

    if (dict.containsKey('status')) {
      final status = dict['status']!;
      result.status = status.toLowerCase();
      result.paid = status.toLowerCase() == 'paid';
    }
    if (dict.containsKey('amount')) result.amount = double.tryParse(dict['amount']!);
    if (dict.containsKey('reference')) result.reference = dict['reference']!;
    if (dict.containsKey('paynowreference')) result.paynowReference = dict['paynowreference']!;

    return result;
  }
}

class PayNowResponse {
  bool success;
  String? reference;
  String? pollUrl;
  String? error;

  PayNowResponse({required this.success, this.reference, this.pollUrl, this.error});
}

class PayNowStatusResponse {
  bool paid;
  String status;
  String? reference;
  double? amount;
  String? paynowReference;
  String? error;

  PayNowStatusResponse({
    required this.paid,
    required this.status,
    this.reference,
    this.amount,
    this.paynowReference,
    this.error,
  });
}