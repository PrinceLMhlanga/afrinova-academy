import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crypto/crypto.dart';

class PayNowService {
  final SupabaseClient _client = Supabase.instance.client;

  String? _integrationId;
  String? _integrationKey;

  String get _baseUrl => 'https://www.paynow.co.zw/interface';
  String get _resultUrl => const String.fromEnvironment(
        'PAYNOW_WEBHOOK_URL',
        defaultValue: 'https://rwheufzhixqqifoleltu.supabase.co/functions/v1/paynow-webhook',
      );
  String get _returnUrl => const String.fromEnvironment(
        'PAYNOW_RETURN_URL',
        defaultValue: 'https://afrinova.academy/payment/complete',
      );

  Future<void> _loadSettings() async {
    if (_integrationId != null) return;

    final response = await _client
        .from('platform_settings')
        .select('key, value')
        .inFilter('key', ['paynow_integration_id', 'paynow_integration_key']);

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

      final amountStr = amount.toStringAsFixed(2);
      final autoEmail = email.trim().isNotEmpty ? email.trim() : '$mobileNumber@mobile.paynow.co.zw';

      final items = <String, String>{
        'id': _integrationId ?? '',
        'reference': reference,
        'amount': amountStr,
        'authemail': autoEmail,
        'additionalinfo': '',
        'returnurl': _returnUrl,
        'resulturl': _resultUrl,
        'status': 'Message',
        'phone': mobileNumber.trim(),
        'method': carrier,
      };

      final hash = _generateHash(items);
      items['hash'] = hash;

      final postData = items.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');

      debugPrint('PayNow Request: $postData');

      final response = await http
          .post(
            Uri.parse('$_baseUrl/remotetransaction'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: postData,
          )
          .timeout(const Duration(seconds: 20));

      debugPrint('PayNow Response: ${response.body}');

      return _parseInitiateResponse(response.body, reference);
    } catch (e) {
      debugPrint('PayNow error: $e');
      return PayNowResponse(success: false, error: e.toString());
    }
  }

  Future<PayNowStatusResponse> pollTransaction(String pollUrl) async {
    try {
      if (pollUrl.isEmpty) {
        return PayNowStatusResponse(paid: false, status: 'Error', error: 'Empty poll URL');
      }

      final decodedUrl = Uri.decodeFull(pollUrl);

      final response = await http
          .post(Uri.parse(decodedUrl), body: '')
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
  }) async {
    // ✅ ALWAYS create a new payment reference
    // Each payment is unique, even for the same student+teacher
    final reference = 'AFRINOVA-${DateTime.now().millisecondsSinceEpoch}';

    await _client.from('payments').insert({
      'student_id': studentId,
      'teacher_id': teacherId,
      'amount': amount,
      'gateway_reference': reference,
      'status': 'pending',
      'payment_method': 'ecocash',
      'enrollment_id': enrollmentId,
      'created_at': DateTime.now().toIso8601String(),
    });

    debugPrint('Created new pending payment: $reference');
    return reference;
  }

  PayNowResponse _parseInitiateResponse(String body, String reference) {
    final result = PayNowResponse(success: false, reference: reference);

    final lines = body.split(RegExp(r'[\r\n&]'));
    for (final line in lines) {
      if (line.isEmpty) continue;
      final separatorIndex = line.indexOf('=');
      if (separatorIndex < 0) continue;

      final key = line.substring(0, separatorIndex).toLowerCase();
      final value = line.substring(separatorIndex + 1);

      if (key == 'pollurl') {
        result.pollUrl = Uri.decodeComponent(value);
      } else if (key == 'status') {
        result.success = Uri.decodeComponent(value).toLowerCase() == 'ok';
      } else if (key == 'error') {
        result.error = Uri.decodeComponent(value);
      }
    }

    return result;
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
    if (dict.containsKey('amount')) {
      result.amount = double.tryParse(dict['amount']!);
    }
    if (dict.containsKey('reference')) {
      result.reference = dict['reference']!;
    }
    if (dict.containsKey('paynowreference')) {
      result.paynowReference = dict['paynowreference']!;
    }

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