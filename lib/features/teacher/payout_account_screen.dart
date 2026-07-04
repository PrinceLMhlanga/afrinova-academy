import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';

class PayoutAccountScreen extends StatefulWidget {
  const PayoutAccountScreen({super.key});

  @override
  State<PayoutAccountScreen> createState() => _PayoutAccountScreenState();
}

class _PayoutAccountScreenState extends State<PayoutAccountScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _accountNameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  String _selectedMethod = 'ecocash';
  List<Map<String, dynamic>> _accounts = [];
  bool _isLoading = true;
  bool _isSaving = false;

  final Map<String, Map<String, String>> _methodInfo = {
    'ecocash': {
      'name': 'EcoCash',
      'icon': '📱',
      'hint': '077 XXXX XXX',
      'prefix': '+263',
    },
    'onemoney': {
      'name': 'OneMoney',
      'icon': '📱',
      'hint': '071 XXXX XXX',
      'prefix': '+263',
    },
    'innbucks': {
      'name': 'InnBucks',
      'icon': '🏦',
      'hint': 'Account number',
      'prefix': '',
    },
    'bank_transfer': {
      'name': 'Bank Transfer',
      'icon': '🏛️',
      'hint': 'Account number',
      'prefix': '',
    },
  };

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      final response = await Supabase.instance.client
          .from('teacher_payout_accounts')
          .select()
          .eq('teacher_id', userId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _accounts = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addAccount() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      await Supabase.instance.client.from('teacher_payout_accounts').insert({
        'teacher_id': userId,
        'method': _selectedMethod,
        'account_name': _accountNameController.text.trim(),
        'account_number': _accountNumberController.text.trim(),
        'is_default': _accounts.isEmpty, // First account is default
      });

      _accountNameController.clear();
      _accountNumberController.clear();
      _loadAccounts();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payout account added! ✅'), backgroundColor: Color(0xFF4CAF50)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteAccount(String accountId) async {
    await Supabase.instance.client
        .from('teacher_payout_accounts')
        .delete()
        .eq('id', accountId);
    _loadAccounts();
  }

  Future<void> _setDefault(String accountId) async {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    // Remove default from all
    await Supabase.instance.client
        .from('teacher_payout_accounts')
        .update({'is_default': false})
        .eq('teacher_id', userId);

    // Set new default
    await Supabase.instance.client
        .from('teacher_payout_accounts')
        .update({'is_default': true})
        .eq('id', accountId);

    _loadAccounts();
  }

  @override
  void dispose() {
    _accountNameController.dispose();
    _accountNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF5F7FA), Color(0xFFE8ECF1)],
          ),
        ),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 120,
              floating: false,
              pinned: true,
              backgroundColor: Colors.transparent,
              leading: const BackButton(color: Colors.white),
              flexibleSpace: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0D1B4C), Color(0xFF1A237E), Color(0xFF283593)],
                  ),
                ),
                child: const FlexibleSpaceBar(
                  title: Text('Payout Accounts',
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
                  // Info card
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.amber, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Add your payout accounts to receive earnings. You can add multiple accounts.',
                            style: TextStyle(fontSize: 13, color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Existing accounts
                  if (_isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (_accounts.isNotEmpty) ...[
                    const Text('Your Accounts',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                    const SizedBox(height: 10),
                    ..._accounts.map((account) {
                      final method = account['method'] as String;
                      final info = _methodInfo[method] ?? {};
                      final isDefault = account['is_default'] == true;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDefault ? const Color(0xFF4CAF50) : Colors.grey.shade200,
                            width: isDefault ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A237E).withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(info['icon'] ?? '💰', style: const TextStyle(fontSize: 22)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(info['name'] ?? method,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      if (isDefault) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF4CAF50).withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text('Default',
                                              style: TextStyle(color: Color(0xFF4CAF50), fontSize: 9, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ],
                                  ),
                                  Text(account['account_number'] ?? '',
                                      style: const TextStyle(fontSize: 13, color: Colors.grey)),
                                ],
                              ),
                            ),
                            if (!isDefault)
                              GestureDetector(
                                onTap: () => _setDefault(account['id'] as String),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A237E).withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.star_outline, size: 18, color: Color(0xFF1A237E)),
                                ),
                              ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => _deleteAccount(account['id'] as String),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 24),
                  ],

                  // Add new account form
                  const Text('Add New Account',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                  const SizedBox(height: 12),

                  Form(
                    key: _formKey,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          // Method selector
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _methodInfo.entries.map((entry) {
                              final isSelected = _selectedMethod == entry.key;
                              return GestureDetector(
                                onTap: () => setState(() => _selectedMethod = entry.key),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFF1A237E) : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${entry.value['icon']} ${entry.value['name']}',
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.black87,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),

                          // Account name
                          TextFormField(
                            controller: _accountNameController,
                            decoration: InputDecoration(
                              labelText: 'Account Name',
                              hintText: 'e.g., John Moyo',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              prefixIcon: const Icon(Icons.person_outline),
                            ),
                            validator: (v) => v!.isEmpty ? 'Enter account name' : null,
                          ),
                          const SizedBox(height: 12),

                          // Account number
                          TextFormField(
                            controller: _accountNumberController,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText: _methodInfo[_selectedMethod]?['hint'] ?? 'Account Number',
                              prefixText: _methodInfo[_selectedMethod]?['prefix'],
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              prefixIcon: const Icon(Icons.numbers),
                            ),
                            validator: (v) => v!.isEmpty ? 'Enter account number' : null,
                          ),
                          const SizedBox(height: 16),

                          // Add button
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: _isSaving ? null : _addAccount,
                              icon: _isSaving
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.add),
                              label: const Text('Add Account'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1A237E),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}