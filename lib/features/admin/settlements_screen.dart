import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class SettlementsScreen extends StatefulWidget {
  const SettlementsScreen({super.key});

  @override
  State<SettlementsScreen> createState() => _SettlementsScreenState();
}

class _SettlementsScreenState extends State<SettlementsScreen> {
  List<Map<String, dynamic>> _teacherWallets = [];
  List<Map<String, dynamic>> _settlementHistory = [];
  bool _isLoading = true;
  
  static const double _minimumThreshold = 20.0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final wallets = await Supabase.instance.client
          .from('teacher_wallets')
          .select('*, profiles!teacher_id(full_name, email, display_name)')
          .gt('available_balance', 0)
          .order('available_balance', ascending: false);

      final settlements = await Supabase.instance.client
          .from('withdrawals')
          .select('*, profiles!teacher_id(full_name, display_name), teacher_payout_accounts(method, account_name, account_number)')
          .order('processed_at', ascending: false)
          .limit(50);

      if (mounted) {
        setState(() {
          _teacherWallets = List<Map<String, dynamic>>.from(wallets);
          _settlementHistory = List<Map<String, dynamic>>.from(settlements);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading settlements: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _settleAllEligible() async {
    final eligible = _teacherWallets.where((w) {
      final available = (w['available_balance'] as num?)?.toDouble() ?? 0;
      return available >= _minimumThreshold;
    }).toList();

    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No teachers have reached the \$${_minimumThreshold.toStringAsFixed(0)} threshold'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final totalAmount = eligible.fold<double>(
        0, (sum, w) => sum + ((w['available_balance'] as num?)?.toDouble() ?? 0));

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Settle All Eligible?'),
        content: Text(
            '${eligible.length} teacher(s) qualify (≥ \$${_minimumThreshold.toStringAsFixed(0)}).\n\n'
            'Total to send: \$${totalAmount.toStringAsFixed(2)}\n\n'
            'Have you sent all Ecocash payments?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50), foregroundColor: Colors.white),
            child: const Text('Yes, All Settled'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    for (final w in eligible) {
      await _settleTeacher(w, showConfirmation: false);
    }
    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${eligible.length} teachers settled! ✅'),
            backgroundColor: const Color(0xFF4CAF50)),
      );
    }
  }

  Future<void> _settleTeacher(Map<String, dynamic> wallet, {bool showConfirmation = true}) async {
    final teacherId = wallet['teacher_id'] as String;
    final amount = (wallet['available_balance'] as num?)?.toDouble() ?? 0;
    final teacherName = wallet['profiles']?['display_name'] ?? wallet['profiles']?['full_name'] ?? 'Teacher';

    // Check threshold for individual settle
    if (amount < _minimumThreshold) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Below minimum threshold of \$${_minimumThreshold.toStringAsFixed(0)}'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Get teacher's payout account for display
    final payoutAccounts = await Supabase.instance.client
        .from('teacher_payout_accounts')
        .select('*')
        .eq('teacher_id', teacherId)
        .order('is_default', ascending: false);

    final defaultAccount = payoutAccounts.isNotEmpty
        ? payoutAccounts.firstWhere(
            (a) => a['is_default'] == true,
            orElse: () => payoutAccounts.first,
          )
        : null;

    final accountName = defaultAccount?['account_name'] as String? ?? 'No payout account';
    final accountNumber = defaultAccount?['account_number'] as String? ?? '';
    final method = defaultAccount?['method'] as String? ?? 'ecocash';

    if (showConfirmation) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Settle $teacherName'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Amount: \$${amount.toStringAsFixed(2)}'),
              const SizedBox(height: 12),
              const Text('Payout Account:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              Text('$method • $accountName'),
              Text(accountNumber),
              const SizedBox(height: 12),
              const Text('Have you sent the payment?'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50), foregroundColor: Colors.white),
              child: const Text('Yes, Settled'),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    try {
      await Supabase.instance.client.rpc('settle_teacher_funds', params: {
        'p_teacher_id': teacherId,
        'p_amount': amount,
        'p_settled_by': Supabase.instance.client.auth.currentUser?.id,
      });

      if (mounted && showConfirmation) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('\$${amount.toStringAsFixed(2)} settled for $teacherName ✅'),
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalAvailable = _teacherWallets.fold<double>(
        0, (sum, w) => sum + ((w['available_balance'] as num?)?.toDouble() ?? 0));
    
    final eligibleCount = _teacherWallets.where((w) {
      final available = (w['available_balance'] as num?)?.toDouble() ?? 0;
      return available >= _minimumThreshold;
    }).length;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF5F7FA), Color(0xFFE8ECF1)]),
        ),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 130,
              floating: false,
              pinned: true,
              backgroundColor: Colors.transparent,
              leading: const BackButton(color: Colors.white),
              flexibleSpace: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Color(0xFF0D1B4C), Color(0xFF1A237E), Color(0xFF283593)]),
                ),
                child: const FlexibleSpaceBar(
                  title: Text('Teacher Settlements',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                  centerTitle: false,
                  titlePadding: EdgeInsets.only(left: 16, bottom: 16),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (_isLoading)
                    const Center(
                        child: Padding(
                            padding: EdgeInsets.all(60),
                            child: CircularProgressIndicator(color: Color(0xFF1A237E))))
                  else ...[
                    // ✅ Payout info banner
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Payouts are processed every Saturday. Minimum threshold: \$${_minimumThreshold.toStringAsFixed(0)}.',
                              style: const TextStyle(fontSize: 12, color: Colors.blue),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Summary cards
                    Row(children: [
                      Expanded(
                          child: _SummaryCard(
                              label: 'Available to Settle',
                              amount: totalAvailable,
                              color: const Color(0xFF4CAF50))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _SummaryCard(
                              label: 'Eligible (≥ \$20)',
                              amount: eligibleCount.toDouble(),
                              color: const Color(0xFF1A237E),
                              isCount: true)),
                    ]),
                    const SizedBox(height: 16),

                    // ✅ Settle All Eligible button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: eligibleCount > 0 ? _settleAllEligible : null,
                        icon: const Icon(Icons.payment_rounded),
                        label: Text(
                          'Settle All Eligible ($eligibleCount teachers ≥ \$20)',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A237E),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Settlements are processed manually via Ecocash.',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),

                    // Teacher list
                    if (_teacherWallets.isEmpty)
                      const Center(
                          child: Padding(
                              padding: EdgeInsets.all(60),
                              child: Text('No teachers with pending balance',
                                  style: TextStyle(color: Colors.grey, fontSize: 16))))
                    else
                      ..._teacherWallets.map((w) {
                        final teacherName = w['profiles']?['display_name'] ?? w['profiles']?['full_name'] ?? 'Unknown';
                        final email = w['profiles']?['email'] ?? '';
                        final available = (w['available_balance'] as num?)?.toDouble() ?? 0;
                        final lifetime = (w['lifetime_earnings'] as num?)?.toDouble() ?? 0;
                        final referralEarnings = (w['referral_earnings'] as num?)?.toDouble() ?? 0;
                        final isEligible = available >= _minimumThreshold;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: isEligible
                                ? Border.all(color: const Color(0xFF4CAF50).withOpacity(0.3))
                                : Border.all(color: Colors.orange.withOpacity(0.3)),
                            boxShadow: [
                              BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 8)
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                CircleAvatar(
                                    radius: 20,
                                    backgroundColor: const Color(0xFF1A237E).withOpacity(0.1),
                                    child: Text(teacherName[0].toUpperCase(),
                                        style: const TextStyle(
                                            color: Color(0xFF1A237E),
                                            fontWeight: FontWeight.bold))),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                      Text(teacherName,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold, fontSize: 15)),
                                      if (email.isNotEmpty)
                                        Text(email,
                                            style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                    ])),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('\$${available.toStringAsFixed(2)}',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: isEligible ? const Color(0xFF4CAF50) : Colors.orange,
                                            fontSize: 18)),
                                    Text(isEligible ? 'Eligible' : 'Below threshold',
                                        style: TextStyle(
                                            fontSize: 9,
                                            color: isEligible ? const Color(0xFF4CAF50) : Colors.orange)),
                                  ],
                                ),
                              ]),
                              const SizedBox(height: 12),
                              Row(children: [
                                _BalanceBadge(
                                    label: 'Lifetime',
                                    amount: lifetime,
                                    color: const Color(0xFF1A237E)),
                                const SizedBox(width: 8),
                                _BalanceBadge(
                                    label: 'Referrals',
                                    amount: referralEarnings,
                                    color: const Color(0xFFE91E63)),
                                const SizedBox(width: 8),
                                if (isEligible)
                                  ElevatedButton(
                                    onPressed: () => _settleTeacher(w),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF4CAF50),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    ),
                                    child: const Text('Settle', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  )
                                else
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '\$${(20 - available).toStringAsFixed(2)} to go',
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                  ),
                              ]),
                            ],
                          ),
                        );
                      }),
                    const SizedBox(height: 24),

                    // Settlement History
                    const Text('Recent Settlements',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                    const SizedBox(height: 12),
                    if (_settlementHistory.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(child: Text('No settlements yet', style: TextStyle(color: Colors.grey))),
                      )
                    else
                      ..._settlementHistory.map((s) {
                        final teacherName = s['profiles']?['display_name'] ?? s['profiles']?['full_name'] ?? 'Teacher';
                        final amount = (s['amount'] as num?)?.toDouble() ?? 0;
                        final processedAt = s['processed_at'] as String?;
                        final payoutAccount = s['teacher_payout_accounts'] as Map<String, dynamic>?;
                        final accountName = payoutAccount?['account_name'] as String? ?? '';
                        final accountNumber = payoutAccount?['account_number'] as String? ?? '';
                        final method = payoutAccount?['method'] as String? ?? 'ecocash';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(teacherName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                    Text(
                                      '${method.toUpperCase()} • $accountName • $accountNumber',
                                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                                    ),
                                    Text(
                                      processedAt != null 
                                          ? DateFormat('MMM d, yyyy HH:mm').format(DateTime.parse(processedAt))
                                          : '',
                                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '\$${amount.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.green),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final bool isCount;

  const _SummaryCard({
    required this.label,
    required this.amount,
    required this.color,
    this.isCount = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 8)],
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(children: [
        Text(
          isCount ? amount.toInt().toString() : '\$${amount.toStringAsFixed(2)}',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ]),
    );
  }
}

class _BalanceBadge extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;

  const _BalanceBadge({
    required this.label,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(children: [
          Text('\$${amount.toStringAsFixed(2)}',
              style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
          Text(label, style: TextStyle(fontSize: 10, color: color)),
        ]),
      ),
    );
  }
}