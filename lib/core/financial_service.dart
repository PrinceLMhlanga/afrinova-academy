import 'package:supabase_flutter/supabase_flutter.dart';

class FinancialService {
  final SupabaseClient _client = Supabase.instance.client;

  // Record a payment and create transactions
  Future<void> processPayment({
    required String studentId,
    required String teacherId,
    required double amount,
    required String gatewayReference,
  }) async {
    final response = await _client.functions.invoke('process-payment', body: {
      'studentId': studentId,
      'teacherId': teacherId,
      'amount': amount,
      'gatewayReference': gatewayReference,
    });

    if (response.data == null || response.data['success'] != true) {
      throw Exception(response.data?['error'] ?? 'Payment processing failed');
    }
  }

  // Get commission for a teacher
  Future<Map<String, dynamic>> _getCommission(String teacherId) async {
    final rule = await _client
        .from('commission_rules')
        .select('platform_percentage, teacher_percentage')
        .eq('teacher_id', teacherId)
        .eq('is_active', true)
        .order('effective_from', ascending: false)
        .maybeSingle();

    if (rule != null) return rule;

    // Default
    return {'platform_percentage': 30, 'teacher_percentage': 70};
  }

  // Get teacher wallet
  Future<Map<String, dynamic>> getWallet(String teacherId) async {
    final wallet = await _client
        .from('teacher_wallets')
        .select()
        .eq('teacher_id', teacherId)
        .maybeSingle();

    return wallet ?? {
      'available_balance': 0,
      'pending_balance': 0,
      'lifetime_earnings': 0,
    };
  }

  // Request withdrawal
  Future<void> requestWithdrawal({
    required String teacherId,
    required double amount,
    required String payoutAccountId,
  }) async {
    await _client.from('withdrawals').insert({
      'teacher_id': teacherId,
      'amount': amount,
      'status': 'pending',
      'payout_account_id': payoutAccountId,
    });
  }

  // Get teacher transactions
  Future<List<Map<String, dynamic>>> getTransactions(String teacherId) async {
    return await _client
        .from('financial_transactions')
        .select()
        .eq('owner_id', teacherId)
        .eq('owner_type', 'teacher')
        .order('created_at', ascending: false)
        .limit(50);
  }

  // Get pricing from database
Future<Map<String, double>> getPricing() async {
  try {
    final response = await _client
        .from('platform_settings')
        .select('key, value')
        .inFilter('key', ['price_monthly', 'price_termly']);

    double monthly = 10;
    double termly = 25;

    for (final row in response) {
      if (row['key'] == 'price_monthly') {
        monthly = double.tryParse(row['value'] as String? ?? '10') ?? 10;
      }
      if (row['key'] == 'price_termly') {
        termly = double.tryParse(row['value'] as String? ?? '25') ?? 25;
      }
    }

    return {'monthly': monthly, 'termly': termly};
  } catch (_) {
    return {'monthly': 10, 'termly': 25};
  }
}
}