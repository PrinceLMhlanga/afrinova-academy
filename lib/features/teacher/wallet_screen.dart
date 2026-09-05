import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/auth_service.dart';

class TeacherWalletScreen extends StatefulWidget {
  const TeacherWalletScreen({super.key});

  @override
  State<TeacherWalletScreen> createState() => _TeacherWalletScreenState();
}

class _TeacherWalletScreenState extends State<TeacherWalletScreen> {
  final AuthService _authService = AuthService();
  
  Map<String, dynamic>? _wallet;
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _settlements = [];
  bool _isLoading = true;
  
  // Date filter
  String _dateFilter = 'all'; // 'week', 'month', 'year', 'all'
  
  // Filtered values
  double _filteredEnrollmentEarnings = 0;
  double _filteredReferralEarnings = 0;
  double _filteredTotalEarnings = 0;
  double _filteredWithdrawn = 0;

  @override
  void initState() {
    super.initState();
    _loadWallet();
  }

  Future<void> _loadWallet() async {
  try {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    final dateRange = _getDateRange();

    // Get wallet
    final wallet = await Supabase.instance.client
        .from('teacher_wallets')
        .select('*')
        .eq('teacher_id', userId)
        .maybeSingle();

    // ✅ Get enrollment transactions with student names
    var txnsQuery = Supabase.instance.client
        .from('financial_transactions')
        .select('''
          *,
          payments!financial_transactions_payment_id_fkey(
            student_id,
            profiles!payments_student_id_fkey(
              full_name,
              display_name
            )
          )
        ''')
        .eq('owner_type', 'teacher')
        .eq('owner_id', userId)
        .eq('type', 'credit');

    if (dateRange != null) {
      final startDate = dateRange['start']!;
      final endDate = dateRange['end']!;
      
      txnsQuery = txnsQuery
          .gte('created_at', startDate)
          .lt('created_at', endDate);
    }

    final enrollmentTransactions = await txnsQuery
        .order('created_at', ascending: false)
        .limit(50);

    // ✅ Get referral earnings with student names
    var referralsQuery = Supabase.instance.client
        .from('referrals')
        .select('''
          *,
          profiles!referred_user_id(full_name, display_name)
        ''')
        .eq('referrer_id', userId)
        .eq('referral_status', 'subscribed')
        .eq('reward_status', 'earned');

    if (dateRange != null) {
      final startDate = dateRange['start']!;
      final endDate = dateRange['end']!;
      
      referralsQuery = referralsQuery
          .gte('rewarded_at', startDate)
          .lt('rewarded_at', endDate);
    }

    final referralTransactions = await referralsQuery
        .order('rewarded_at', ascending: false)
        .limit(50);

    // Get settlements (withdrawals)
    var settlementsQuery = Supabase.instance.client
        .from('withdrawals')
        .select('*')
        .eq('teacher_id', userId);

    if (dateRange != null) {
      final startDate = dateRange['start']!;
      final endDate = dateRange['end']!;
      
      settlementsQuery = settlementsQuery
          .gte('processed_at', startDate)
          .lt('processed_at', endDate);
    }

    final settlements = await settlementsQuery
        .order('processed_at', ascending: false)
        .limit(50);

    // Calculate filtered values
    double filteredEnrollment = 0;
    for (final t in enrollmentTransactions) {
      filteredEnrollment += (t['amount'] as num?)?.toDouble() ?? 0;
    }
    
    final referralCount = referralTransactions.length;
    final filteredReferral = referralCount * 2.0;
    final filteredTotal = filteredEnrollment + filteredReferral;
    
    double filteredWithdrawn = 0;
    for (final s in settlements) {
      filteredWithdrawn += (s['amount'] as num?)?.toDouble() ?? 0;
    }

    // ✅ Build combined transaction list for display
    final combinedTransactions = <Map<String, dynamic>>[];
    
    // Add enrollment transactions
    for (final t in enrollmentTransactions) {
      final payments = t['payments'] as Map<String, dynamic>?;
      final profiles = payments?['profiles'] as Map<String, dynamic>?;
      
      combinedTransactions.add({
        'type': 'enrollment',
        'amount': (t['amount'] as num?)?.toDouble() ?? 0,
        'created_at': t['created_at'],
        'student_name': profiles?['display_name'] ?? profiles?['full_name'] ?? 'Student',
        'description': 'Enrollment payment',
      });
    }
    
    // Add referral transactions
    for (final r in referralTransactions) {
      final profiles = r['profiles'] as Map<String, dynamic>?;
      
      combinedTransactions.add({
        'type': 'referral',
        'amount': 2.0,
        'created_at': r['rewarded_at'],
        'student_name': profiles?['display_name'] ?? profiles?['full_name'] ?? 'Student',
        'description': 'Referral reward',
      });
    }
    
    // Sort combined by date
    combinedTransactions.sort((a, b) {
      final aDate = a['created_at'] as String? ?? '';
      final bDate = b['created_at'] as String? ?? '';
      return bDate.compareTo(aDate);
    });

    if (mounted) {
      setState(() {
        _wallet = wallet;
        _transactions = combinedTransactions;
        _settlements = List<Map<String, dynamic>>.from(settlements);
        _filteredEnrollmentEarnings = filteredEnrollment;
        _filteredReferralEarnings = filteredReferral;
        _filteredTotalEarnings = filteredTotal;
        _filteredWithdrawn = filteredWithdrawn;
        _isLoading = false;
      });
    }
  } catch (e) {
    debugPrint('Error loading wallet: $e');
    if (mounted) setState(() => _isLoading = false);
  }
}

  Map<String, String>? _getDateRange() {
    final now = DateTime.now();
    DateTime start;
    DateTime end = now;

    switch (_dateFilter) {
      case 'week':
        start = now.subtract(Duration(days: now.weekday - 1));
        start = DateTime(start.year, start.month, start.day);
        break;
      case 'month':
        start = DateTime(now.year, now.month, 1);
        break;
      case 'year':
        start = DateTime(now.year, 1, 1);
        break;
      default:
        return null;
    }

    return {
      'start': start.toIso8601String(),
      'end': end.add(const Duration(days: 1)).toIso8601String(),
    };
  }

  String _getFilterLabel() {
    switch (_dateFilter) {
      case 'week': return 'THIS WEEK';
      case 'month': return 'THIS MONTH';
      case 'year': return 'THIS YEAR';
      default: return 'ALL TIME';
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableBalance = (_wallet?['available_balance'] as num?)?.toDouble() ?? 0;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('My Wallet'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadWallet,
              color: const Color(0xFF1A237E),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date Filter Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('This Week', 'week'),
                          const SizedBox(width: 8),
                          _buildFilterChip('This Month', 'month'),
                          const SizedBox(width: 8),
                          _buildFilterChip('This Year', 'year'),
                          const SizedBox(width: 8),
                          _buildFilterChip('All Time', 'all'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ✅ BLUE CARD - Total Earnings
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1A237E), Color(0xFF283593)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          // Filter badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _getFilterLabel(),
                              style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Total Earnings',
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '\$${_filteredTotalEarnings.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Children: Enrollment + Referral
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildRevenueItem(
                                'Enrollment',
                                _filteredEnrollmentEarnings,
                                Icons.school,
                              ),
                              _buildRevenueItem(
                                'Referrals',
                                _filteredReferralEarnings,
                                Icons.card_giftcard,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ✅ AVAILABLE BALANCE CARD with payout info
Container(
  padding: const EdgeInsets.all(20),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.3)),
  ),
  child: Column(
    children: [
      // Available Balance Row
      Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.account_balance_wallet, color: Color(0xFF4CAF50), size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Available Balance',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Text(
                  '\$${(_wallet?['available_balance'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4CAF50),
                  ),
                ),
              ],
            ),
          ),
          const Text(
            'CURRENT',
            style: TextStyle(fontSize: 9, color: Colors.green, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      
      const SizedBox(height: 16),
      const Divider(height: 1),
      const SizedBox(height: 12),
      
      // Payout Info
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            availableBalance >= 20 ? Icons.check_circle : Icons.info_outline,
            color: availableBalance >= 20 ? Colors.green : Colors.orange,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  availableBalance >= 20
                      ? 'You\'re eligible for payout! 🎉'
                      : '\$${(20 - availableBalance).toStringAsFixed(2)} more to reach payout minimum',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: availableBalance >= 20 ? Colors.green : Colors.orange,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Payouts are processed every Saturday via EcoCash or Bank Transfer.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const Text(
                  'Minimum payout: \$20',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    ],
  ),
),
                    const SizedBox(height: 16),

                    // Stats Row
                    Row(
                      children: [
                        _buildStatCard(
                          'Total Withdrawn',
                          '\$${_filteredWithdrawn.toStringAsFixed(2)}',
                          Icons.arrow_upward,
                          const Color(0xFF4CAF50),
                        ),
                        const SizedBox(width: 12),
                        _buildStatCard(
                          'Settlements',
                          '${_settlements.length}',
                          Icons.receipt_long,
                          const Color(0xFFFF9800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Transaction History
                    Text(
                      'Transaction History (${_transactions.length + _settlements.length})',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),

                    if (_transactions.isEmpty && _settlements.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: const Center(
                          child: Text('No transactions for this period', style: TextStyle(color: Colors.grey)),
                        ),
                      )
                    else ...[
                      if (_transactions.isNotEmpty) ...[
                        const Text(
                          'MONEY IN',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                        const SizedBox(height: 8),
                        ..._transactions.map((t) => _buildTransactionTile(t)),
                      ],
                      
                      if (_settlements.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'MONEY OUT',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red),
                        ),
                        const SizedBox(height: 8),
                        ..._settlements.map((s) => _buildSettlementTile(s)),
                      ],
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildRevenueItem(String label, double amount, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 24),
        const SizedBox(height: 4),
        Text(
          '\$${amount.toStringAsFixed(2)}',
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _dateFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _dateFilter = value;
        });
        _loadWallet();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1A237E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF1A237E) : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionTile(Map<String, dynamic> txn) {
  final amount = txn['amount'] as double? ?? 0;
  final createdAt = txn['created_at'] as String?;
  final studentName = txn['student_name'] as String? ?? 'Student';
  final description = txn['description'] as String? ?? '';
  final type = txn['type'] as String? ?? 'enrollment';
  
  // Different colors for enrollment vs referral
  final isReferral = type == 'referral';
  final color = isReferral ? const Color(0xFFE91E63) : Colors.green;
  final icon = isReferral ? Icons.card_giftcard : Icons.arrow_downward;

  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withOpacity(0.2)),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(studentName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              Text(
                description,
                style: TextStyle(fontSize: 11, color: isReferral ? const Color(0xFFE91E63) : Colors.grey),
              ),
              Text(
                createdAt != null 
                    ? DateFormat('MMM d, yyyy • HH:mm').format(DateTime.parse(createdAt))
                    : '',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ),
        Text(
          '+\$${amount.toStringAsFixed(2)}',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    ),
  );
}

  Widget _buildSettlementTile(Map<String, dynamic> settlement) {
    final amount = settlement['amount'] as num? ?? 0;
    final processedAt = settlement['processed_at'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.arrow_upward, color: Colors.red, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Settlement', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                Text(
                  processedAt != null 
                      ? DateFormat('MMM d, yyyy • HH:mm').format(DateTime.parse(processedAt))
                      : '',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          Text(
            '-\$${amount.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red),
          ),
        ],
      ),
    );
  }
}