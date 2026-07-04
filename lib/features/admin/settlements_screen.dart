import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SettlementsScreen extends StatefulWidget {
  const SettlementsScreen({super.key});

  @override
  State<SettlementsScreen> createState() => _SettlementsScreenState();
}

class _SettlementsScreenState extends State<SettlementsScreen> {
  List<Map<String, dynamic>> _teacherWallets = [];
  bool _isLoading = true;

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
          .select('*, profiles!teacher_id(full_name, email)')
          .order('available_balance', ascending: false);

      if (mounted) {
        setState(() {
          _teacherWallets = List<Map<String, dynamic>>.from(wallets);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _settleAllEligible() async {
    final eligible = _teacherWallets.where((w) {
      final available = (w['available_balance'] as num?)?.toDouble() ?? 0;
      return available >= 20;
    }).toList();

    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No teachers have reached the \$20 threshold yet')),
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
            '${eligible.length} teacher(s) qualify.\n\n'
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
      await _settleTeacher(w);
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

  Future<void> _settleTeacher(Map<String, dynamic> wallet) async {
    final teacherId = wallet['teacher_id'] as String;
    final amount = (wallet['available_balance'] as num?)?.toDouble() ?? 0;

    // Create withdrawal record
    final withdrawal = await Supabase.instance.client
        .from('withdrawals')
        .insert({
          'teacher_id': teacherId,
          'amount': amount,
          'status': 'completed',
          'processed_at': DateTime.now().toIso8601String(),
        })
        .select('id')
        .single();

    // Create debit transaction
    await Supabase.instance.client.from('financial_transactions').insert({
      'withdrawal_id': withdrawal['id'],
      'owner_type': 'teacher',
      'owner_id': teacherId,
      'amount': amount,
      'type': 'debit',
      'description': 'Weekly settlement',
    });

    // Reset available balance
    await Supabase.instance.client.from('teacher_wallets').upsert(
      {
        'teacher_id': teacherId,
        'available_balance': 0,
        'last_updated': DateTime.now().toIso8601String(),
      },
      onConflict: 'teacher_id',
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalPending =
        _teacherWallets.fold<double>(0, (sum, w) => sum + ((w['pending_balance'] as num?)?.toDouble() ?? 0));
    final totalAvailable =
        _teacherWallets.fold<double>(0, (sum, w) => sum + ((w['available_balance'] as num?)?.toDouble() ?? 0));
    final eligibleCount = _teacherWallets
        .where((w) => ((w['available_balance'] as num?)?.toDouble() ?? 0) >= 20)
        .length;

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
                    // Summary cards
                    Row(children: [
                      Expanded(
                          child: _SummaryCard(
                              label: 'Total Pending',
                              amount: totalPending,
                              color: Colors.orange)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _SummaryCard(
                              label: 'Available to Settle',
                              amount: totalAvailable,
                              color: const Color(0xFF4CAF50))),
                    ]),
                    const SizedBox(height: 16),

                    // Settle All button
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
                      'Payouts are processed weekly. Teachers see their balances on their dashboard.',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),

                    // Teacher list
                    if (_teacherWallets.isEmpty)
                      const Center(
                          child: Padding(
                              padding: EdgeInsets.all(60),
                              child: Text('No teacher wallets yet',
                                  style: TextStyle(color: Colors.grey, fontSize: 16))))
                    else
                      ..._teacherWallets.map((w) {
                        final teacherName = w['profiles']?['full_name'] ?? 'Unknown';
                        final email = w['profiles']?['email'] ?? '';
                        final available =
                            (w['available_balance'] as num?)?.toDouble() ?? 0;
                        final pending =
                            (w['pending_balance'] as num?)?.toDouble() ?? 0;
                        final lifetime =
                            (w['lifetime_earnings'] as num?)?.toDouble() ?? 0;
                        final isEligible = available >= 20;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: isEligible
                                ? Border.all(color: const Color(0xFF4CAF50).withOpacity(0.3))
                                : null,
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.grey.withOpacity(0.06),
                                  blurRadius: 8)
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                CircleAvatar(
                                    radius: 20,
                                    backgroundColor:
                                        const Color(0xFF1A237E).withOpacity(0.1),
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
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15)),
                                      if (email.isNotEmpty)
                                        Text(email,
                                            style: const TextStyle(
                                                fontSize: 11, color: Colors.grey)),
                                    ])),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('\$${lifetime.toStringAsFixed(2)}',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF1A237E)
                                                .withOpacity(0.6),
                                            fontSize: 13)),
                                    const Text('Lifetime',
                                        style: TextStyle(
                                            fontSize: 9, color: Colors.grey)),
                                  ],
                                ),
                              ]),
                              const SizedBox(height: 12),
                              Row(children: [
                                _BalanceBadge(
                                    label: 'Available',
                                    amount: available,
                                    color: const Color(0xFF4CAF50),
                                    isEligible: isEligible),
                                const SizedBox(width: 8),
                                _BalanceBadge(
                                    label: 'Pending',
                                    amount: pending,
                                    color: Colors.orange,
                                    isEligible: false),
                              ]),
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

  const _SummaryCard({required this.label, required this.amount, required this.color});

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
        Text('\$${amount.toStringAsFixed(2)}',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
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
  final bool isEligible;

  const _BalanceBadge({
    required this.label,
    required this.amount,
    required this.color,
    this.isEligible = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: isEligible ? Border.all(color: color.withOpacity(0.4)) : null,
        ),
        child: Column(children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('\$${amount.toStringAsFixed(2)}',
                  style: TextStyle(fontWeight: FontWeight.bold, color: color)),
              if (isEligible) ...[
                const SizedBox(width: 4),
                const Icon(Icons.check_circle, size: 14, color: Color(0xFF4CAF50)),
              ],
            ],
          ),
          Text(label, style: TextStyle(fontSize: 10, color: color)),
        ]),
      ),
    );
  }
}