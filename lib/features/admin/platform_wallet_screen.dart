import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class PlatformWalletScreen extends StatefulWidget {
  const PlatformWalletScreen({super.key});

  @override
  State<PlatformWalletScreen> createState() => _PlatformWalletScreenState();
}

class _PlatformWalletScreenState extends State<PlatformWalletScreen> {
  bool _isLoading = true;
  Map<String, dynamic> _wallet = {};
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _withdrawals = [];
  
  double _totalRevenue = 0;
  double _aiRevenue = 0;
  double _enrollmentRevenue = 0;
  
  // ✅ Date filter
  String _dateFilter = 'all'; // 'today', 'week', 'month', 'year', 'all', 'custom'
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  
  // ✅ Filtered stats
  double _filteredTotalRevenue = 0;
  double _filteredAiRevenue = 0;
  double _filteredEnrollmentRevenue = 0;

  @override
  void initState() {
    super.initState();
    _loadWalletData();
  }
  
  // ✅ Get date range based on filter
  Map<String, String>? _getDateRange() {
    final now = DateTime.now();
    DateTime start;
    DateTime end = now;
    
    switch (_dateFilter) {
      case 'today':
        start = DateTime(now.year, now.month, now.day);
        break;
      case 'week':
        start = now.subtract(Duration(days: now.weekday - 1)); // Monday
        start = DateTime(start.year, start.month, start.day);
        break;
      case 'month':
        start = DateTime(now.year, now.month, 1);
        break;
      case 'year':
        start = DateTime(now.year, 1, 1);
        break;
      case 'custom':
        if (_customStartDate == null) return null;
        start = _customStartDate!;
        end = _customEndDate ?? now;
        break;
      default:
        return null; // 'all' - no filter
    }
    
    return {
      'start': start.toIso8601String(),
      'end': end.add(const Duration(days: 1)).toIso8601String(), // Include full day
    };
  }

  Future<void> _loadWalletData() async {
    try {
    final dateRange = _getDateRange();
    
    // ✅ Get wallet stats from database
    final statsResponse = await Supabase.instance.client
        .rpc('get_platform_wallet_stats');
    
    final stats = statsResponse != null && statsResponse.isNotEmpty
        ? statsResponse[0]
        : null;
    
    // ✅ Get recent transactions with date filter
    var txnsQuery = Supabase.instance.client
        .from('platform_transaction_history')
        .select('*');
    
    if (dateRange != null) {
      final startDate = dateRange['start']!;  // ✅ Use ! to assert non-null
      final endDate = dateRange['end']!;      // ✅ Use ! to assert non-null
      
      txnsQuery = txnsQuery
          .gte('created_at', startDate)
          .lt('created_at', endDate);
    }
    
    final recentTxns = await txnsQuery
        .order('created_at', ascending: false)
        .limit(50);
    
    // ✅ Get withdrawals with date filter
    var withdrawalsQuery = Supabase.instance.client
        .from('platform_withdrawals')
        .select();
    
    if (dateRange != null) {
      final startDate = dateRange['start']!;
      final endDate = dateRange['end']!;
      
      withdrawalsQuery = withdrawalsQuery
          .gte('requested_at', startDate)
          .lt('requested_at', endDate);
    }
    
    final withdrawals = await withdrawalsQuery
        .order('requested_at', ascending: false)
        .limit(50);
      
      // ✅ Calculate filtered stats
      double filteredAi = 0;
      double filteredEnrollment = 0;
      
      for (final t in recentTxns) {
        final paymentType = t['payment_type'] as String?;
        final amount = (t['amount'] as num?)?.toDouble() ?? 0;
        
        if (paymentType == 'ai_subscription') {
          filteredAi += amount;
        } else {
          filteredEnrollment += amount;
        }
      }
      
      if (mounted) {
        setState(() {
          if (stats != null) {
            // Lifetime stats (always show lifetime in wallet)
            _totalRevenue = (stats['total_revenue'] as num?)?.toDouble() ?? 0;
            _aiRevenue = (stats['ai_premium_revenue'] as num?)?.toDouble() ?? 0;
            _enrollmentRevenue = (stats['enrollment_revenue'] as num?)?.toDouble() ?? 0;
            _wallet = {
              'available_balance': stats['available_balance'] ?? 0,
              'pending_balance': stats['pending_balance'] ?? 0,
              'lifetime_earnings': stats['lifetime_earnings'] ?? 0,
              'total_withdrawn': stats['total_withdrawn'] ?? 0,
            };
          }
          
          // ✅ Filtered stats (what's shown based on date filter)
          if (_dateFilter == 'all') {
            _filteredTotalRevenue = _totalRevenue;
            _filteredAiRevenue = _aiRevenue;
            _filteredEnrollmentRevenue = _enrollmentRevenue;
          } else {
            _filteredTotalRevenue = filteredAi + filteredEnrollment;
            _filteredAiRevenue = filteredAi;
            _filteredEnrollmentRevenue = filteredEnrollment;
          }
          
          _transactions = List<Map<String, dynamic>>.from(recentTxns);
          _withdrawals = List<Map<String, dynamic>>.from(withdrawals);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading wallet: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showWithdrawDialog() async {
    final amountController = TextEditingController();
    final accountController = TextEditingController();
    String method = 'ecocash';
    String? selectedRecipientId; // null = self
    String recipientType = 'self'; // 'self' or 'admin' or 'other'
    
    // ✅ Load admins for recipient selection
    List<Map<String, dynamic>> admins = [];
    bool isLoadingAdmins = true;
    
    // Load admins
    try {
      final adminsResponse = await Supabase.instance.client
          .from('profiles')
          .select('id, full_name, display_name, email')
          .eq('role', 'admin');
      admins = List<Map<String, dynamic>>.from(adminsResponse);
    } catch (e) {
      debugPrint('Error loading admins: $e');
    }
    
    isLoadingAdmins = false;
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Withdraw Funds'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Who is receiving the money
                  DropdownButtonFormField<String>(
                    initialValue: 'self',
                    items: [
                      const DropdownMenuItem(
                        value: 'self',
                        child: Row(
                          children: [
                            Icon(Icons.person, size: 18),
                            SizedBox(width: 8),
                            Text('Self (My Account)'),
                          ],
                        ),
                      ),
                      // ✅ Load admins (partners) dynamically
                      ...admins.map((admin) {
                        final adminId = admin['id'] as String;
                        final adminName = admin['display_name'] ?? admin['full_name'] ?? 'Partner';
                        final currentUserId = Supabase.instance.client.auth.currentUser?.id;
                        
                        // Skip self (already have "Self" option)
                        if (adminId == currentUserId) {
                          return const DropdownMenuItem(value: 'skip', child: SizedBox.shrink());
                        }
                        
                        return DropdownMenuItem(
                          value: adminId,
                          child: Row(
                            children: [
                              const Icon(Icons.business_center, size: 18),
                              const SizedBox(width: 8),
                              Text(adminName),
                            ],
                          ),
                        );
                      }),
                      const DropdownMenuItem(
                        value: 'other',
                        child: Row(
                          children: [
                            Icon(Icons.person_add, size: 18),
                            SizedBox(width: 8),
                            Text('Other'),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      setDialogState(() {
                        selectedRecipientId = v;
                        recipientType = v == 'self' 
                            ? 'self' 
                            : v == 'other' 
                                ? 'other' 
                                : 'admin';
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Recipient',
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Amount
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Amount (USD)',
                      prefixText: '\$ ',
                      prefixIcon: Icon(Icons.attach_money),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Withdrawal method
                  DropdownButtonFormField<String>(
                    initialValue: 'ecocash',
                    items: const [
                      DropdownMenuItem(value: 'ecocash', child: Text('EcoCash')),
                      DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Transfer')),
                      DropdownMenuItem(value: 'cash', child: Text('Cash')),
                      DropdownMenuItem(value: 'paypal', child: Text('PayPal')),
                    ],
                    onChanged: (v) {
                      setDialogState(() {
                        method = v ?? 'ecocash';
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Withdrawal Method',
                      prefixIcon: Icon(Icons.payment),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Account details
                  TextField(
                    controller: accountController,
                    decoration: const InputDecoration(
                      labelText: 'Account Details',
                      hintText: 'e.g., 077XXXXXXX or Account Number',
                      prefixIcon: Icon(Icons.account_balance_wallet),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final amount = double.tryParse(amountController.text) ?? 0;
                  if (amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enter valid amount'), backgroundColor: Colors.red),
                    );
                    return;
                  }
                  
                  // Determine recipient name
                  String recipientName = 'Self';
                  if (recipientType == 'admin' && selectedRecipientId != null) {
                    final admin = admins.firstWhere(
                      (a) => a['id'] == selectedRecipientId,
                      orElse: () => {'display_name': 'Partner', 'full_name': 'Partner'},
                    );
                    recipientName = admin['display_name'] ?? admin['full_name'] ?? 'Partner';
                  } else if (recipientType == 'other') {
                    recipientName = 'Other';
                  }
                  
                  try {
                    // Call database function
                    await Supabase.instance.client.rpc('request_platform_withdrawal', params: {
                      'p_amount': amount,
                      'p_withdrawal_method': method,
                      'p_destination_details': {
                        'account': accountController.text,
                        'recipient_type': recipientType,
                        'recipient_name': recipientName,
                        'recipient_id': selectedRecipientId,
                      },
                      'p_requested_by': Supabase.instance.client.auth.currentUser?.id,
                    });
                    
                    Navigator.pop(ctx);
                    _loadWalletData();
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('\$${amount.toStringAsFixed(2)} withdrawn by $recipientName ✅'),
                        backgroundColor: const Color(0xFF4CAF50),
                      ),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Confirm Withdrawal'),
              ),
            ],
          );
        },
      ),
    );
  }

  
  // ✅ Show custom date range picker
  Future<void> _showCustomDateRangePicker() async {
    final DateTimeRange? result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customStartDate != null && _customEndDate != null
          ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
          : null,
    );
    
    if (result != null) {
      setState(() {
        _dateFilter = 'custom';
        _customStartDate = result.start;
        _customEndDate = result.end;
      });
      _loadWalletData();
    }
  }
  
  // ✅ Get filter label for badge
  String _getFilterLabel() {
    switch (_dateFilter) {
      case 'today': return 'TODAY';
      case 'week': return 'THIS WEEK';
      case 'month': return 'THIS MONTH';
      case 'year': return 'THIS YEAR';
      case 'custom': return 'CUSTOM RANGE';
      default: return 'LIFETIME';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Platform Wallet'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadWalletData,
              color: const Color(0xFF1A237E),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ✅ Date Filter Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('Today', 'today'),
                          const SizedBox(width: 8),
                          _buildFilterChip('Week', 'week'),
                          const SizedBox(width: 8),
                          _buildFilterChip('Month', 'month'),
                          const SizedBox(width: 8),
                          _buildFilterChip('Year', 'year'),
                          const SizedBox(width: 8),
                          _buildFilterChip('All Time', 'all'),
                          const SizedBox(width: 8),
                          _buildFilterChip('Custom', 'custom'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Lifetime Revenue Card
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
                          // ✅ Dynamic badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _dateFilter == 'all' ? Icons.history : Icons.date_range,
                                  color: Colors.white70,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _getFilterLabel(),
                                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '\$${_filteredTotalRevenue.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildRevenueItem('AI Premium', _filteredAiRevenue, '🤖'),
                              _buildRevenueItem('Enrollments', _filteredEnrollmentRevenue, '📚'),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    
                   // Available Balance + Total Withdrawn cards
Row(
  children: [
    // Available Balance Card
    Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.green.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.savings, color: Colors.green, size: 16),
                ),
                const SizedBox(width: 8),
                const Text('Available', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '\$${(_wallet['available_balance'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green),
            ),
          ],
        ),
      ),
    ),
    const SizedBox(width: 12),
    
    // Total Withdrawn Card
    Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.arrow_upward, color: Colors.red, size: 16),
                ),
                const SizedBox(width: 8),
                const Text('Withdrawn', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '\$${(_wallet['total_withdrawn'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red),
            ),
          ],
        ),
      ),
    ),
  ],
),
const SizedBox(height: 12),

// Withdraw Button
SizedBox(
  width: double.infinity,
  height: 48,
  child: ElevatedButton.icon(
    onPressed: _showWithdrawDialog,
    icon: const Icon(Icons.account_balance_wallet),
    label: const Text('Withdraw Funds'),
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF4CAF50),
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
),
                    const SizedBox(height: 20),
                    
                    // Revenue Breakdown (Filtered)
                    Row(
                      children: [
                        const Text('Revenue Breakdown', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A237E).withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _getFilterLabel(),
                            style: const TextStyle(fontSize: 10, color: Color(0xFF1A237E), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildBreakdownCard(),
                    const SizedBox(height: 20),
                    
                    // Transaction History
                    Text(
                      'Transaction History (${_transactions.length})',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    if (_transactions.isEmpty)
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
                    else
                      ..._transactions.map((t) => _buildTransactionTile(t)),
                    
                    // Withdrawals
                    if (_withdrawals.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Withdrawals (${_withdrawals.length})',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      ..._withdrawals.map((w) => _buildWithdrawalTile(w)),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
  
  // ✅ Build filter chip
  Widget _buildFilterChip(String label, String value) {
    final isSelected = _dateFilter == value;
    return GestureDetector(
      onTap: () {
        if (value == 'custom') {
          _showCustomDateRangePicker();
        } else {
          setState(() {
            _dateFilter = value;
          });
          _loadWalletData();
        }
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
  
  Widget _buildRevenueItem(String label, double amount, String emoji) {
  return Column(
    children: [
      Text(emoji, style: const TextStyle(fontSize: 24)),
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
      // ✅ Show filter label instead of always "LIFETIME"
      Text(
        _getFilterLabel(),
        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 7, fontWeight: FontWeight.w500),
      ),
    ],
  );
}

  Widget _buildBreakdownCard() {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Column(
      children: [
        _buildBreakdownRow('AI Premium (100%)', _filteredAiRevenue, Colors.pink),
        const Divider(height: 20),
        _buildBreakdownRow('Enrollment Platform Fee', _filteredEnrollmentRevenue, Colors.blue),
        const Divider(height: 20),
        _buildBreakdownRow('Total Revenue', _filteredTotalRevenue, const Color(0xFF1A237E)),
      ],
    ),
  );
}

  Widget _buildBreakdownRow(String label, double amount, Color color) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
        Text(
          '\$${amount.toStringAsFixed(2)}',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

Widget _buildTransactionTile(Map<String, dynamic> txn) {
  final amount = txn['amount'] as num? ?? 0;
  final description = txn['description'] as String? ?? '';
  final createdAt = txn['created_at'] as String?;
  final studentName = txn['student_name'] as String? ?? 'Student';
  final paymentType = txn['payment_type'] as String?;
  
  String title;
  String subtitle;
  IconData icon;
  Color iconColor;
  Color amountColor;
  
  if (paymentType == 'ai_subscription') {
    title = studentName;
    subtitle = 'AI Premium Subscription';
    icon = Icons.auto_awesome;
    iconColor = const Color(0xFFE91E63);
    amountColor = const Color(0xFFE91E63);
  } else {
    title = studentName;
    subtitle = 'Enrollment Platform Fee';
    icon = Icons.school;
    iconColor = const Color(0xFF00897B);
    amountColor = const Color(0xFF00897B);
  }
  
  final formattedDate = createdAt != null 
      ? DateFormat('MMM d, yyyy • HH:mm').format(DateTime.parse(createdAt)) 
      : '';
  
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade200),
      boxShadow: [
        BoxShadow(
          color: Colors.grey.withOpacity(0.05),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          // Icon container
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          
          // Student name and details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formattedDate,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(width: 8),
          
          // Amount
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '+\$${amount.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: amountColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'CREDIT',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  color: amountColor.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
Widget _buildWithdrawalTile(Map<String, dynamic> withdrawal) {
  final amount = withdrawal['amount'] as num? ?? 0;
  final status = withdrawal['status'] as String? ?? 'completed';
  final requestedAt = withdrawal['requested_at'] as String?;
  final destinationDetails = withdrawal['destination_details'] as Map<String, dynamic>?;
  final recipientName = destinationDetails?['recipient_name'] as String? ?? 'Self';
  final recipientType = destinationDetails?['recipient_type'] as String? ?? 'self';
  final method = withdrawal['withdrawal_method'] as String? ?? 'ecocash';
  
  IconData recipientIcon;
  Color recipientColor;
  switch (recipientType) {
    case 'admin':
      recipientIcon = Icons.business_center;
      recipientColor = Colors.blue;
      break;
    case 'other':
      recipientIcon = Icons.person_add;
      recipientColor = Colors.purple;
      break;
    default:
      recipientIcon = Icons.person;
      recipientColor = Colors.grey;
      break;
  }
  
  final formattedDate = requestedAt != null 
      ? DateFormat('MMM d, yyyy • HH:mm').format(DateTime.parse(requestedAt)) 
      : '';
  
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.red.withOpacity(0.2)),
      boxShadow: [
        BoxShadow(
          color: Colors.grey.withOpacity(0.05),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          // Icon container
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: recipientColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(recipientIcon, color: recipientColor, size: 20),
          ),
          const SizedBox(width: 12),
          
          // Recipient and details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recipientName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Withdrawal • ${method.toUpperCase()}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formattedDate,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(width: 8),
          
          // Amount
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '-\$${amount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'DEBIT',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  color: Colors.red.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

}