import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlatformSettingsScreen extends StatefulWidget {
  const PlatformSettingsScreen({super.key});

  @override
  State<PlatformSettingsScreen> createState() => _PlatformSettingsScreenState();
}

class _PlatformSettingsScreenState extends State<PlatformSettingsScreen> {
  List<Map<String, dynamic>> _settings = [];
  Map<String, TextEditingController> _controllers = {};
  bool _isLoading = true;
  bool _isSaving = false;

  // Settings to show in app (filter out sensitive ones)
  final _visibleKeys = [
    'price_monthly',
    'price_termly',
    'default_commission',
    'settlement_threshold',
    'currency',
    'trial_days',
  ];

  final _settingLabels = {
    'price_monthly': 'Monthly Price (USD)',
    'price_termly': 'Termly Price (USD)',
    'default_commission': 'Default Commission (Platform:Teacher)',
    'settlement_threshold': 'Settlement Threshold (USD)',
    'currency': 'Currency',
    'trial_days': 'Trial Period (Days)',
  };

  final _settingDescriptions = {
    'price_monthly': 'Price for 30-day access to a subject',
    'price_termly': 'Price for 90-day access to a subject',
    'default_commission': 'Format: platform_percentage:teacher_percentage (e.g., 30:70)',
    'settlement_threshold': 'Minimum amount before teacher can receive payout',
    'currency': 'Currency code (e.g., USD)',
    'trial_days': 'Number of days for free trial period',
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final response = await Supabase.instance.client
          .from('platform_settings')
          .select()
          .inFilter('key', _visibleKeys);

      if (mounted) {
        setState(() {
          _settings = List<Map<String, dynamic>>.from(response);
          // Create controllers for each setting
          for (final setting in _settings) {
            final key = setting['key'] as String;
            if (!_controllers.containsKey(key)) {
              _controllers[key] = TextEditingController(text: setting['value'] as String? ?? '');
            }
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveAllSettings() async {
    setState(() => _isSaving = true);
    try {
      for (final setting in _settings) {
        final key = setting['key'] as String;
        final controller = _controllers[key];
        if (controller == null) continue;

        final newValue = controller.text.trim();
        if (newValue.isEmpty) continue;

        await Supabase.instance.client
            .from('platform_settings')
            .update({
              'value': newValue,
            })
            .eq('key', key);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved! ✅'), backgroundColor: Color(0xFF4CAF50)),
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

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform Settings'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _saveAllSettings,
            icon: _isSaving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save, color: Colors.white),
            label: const Text('Save All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A237E).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF1A237E).withOpacity(0.1)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.settings, color: Color(0xFF1A237E), size: 24),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'These settings affect the entire platform. Changes take effect immediately.',
                          style: TextStyle(fontSize: 13, color: Color(0xFF1A237E)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Settings cards
                ..._settings.map((setting) {
                  final key = setting['key'] as String;
                  final label = _settingLabels[key] ?? key;
                  final description = _settingDescriptions[key] ?? setting['description'] ?? '';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 8)],
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _getSettingIcon(key),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(label,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                            ),
                          ],
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(description, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _controllers[key],
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          keyboardType: _getKeyboardType(key),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 20),

                // Save button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveAllSettings,
                    icon: _isSaving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: const Text('Save All Settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A237E),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text('Settings are saved to the database and take effect immediately.',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                ),
              ],
            ),
    );
  }

  Widget _getSettingIcon(String key) {
    switch (key) {
      case 'price_monthly':
      case 'price_termly':
        return Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF4CAF50).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.attach_money, color: Color(0xFF4CAF50), size: 20),
        );
      case 'default_commission':
        return Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFFF9800).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.pie_chart, color: Color(0xFFFF9800), size: 20),
        );
      case 'settlement_threshold':
        return Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: Colors.purple.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.account_balance_wallet, color: Colors.purple, size: 20),
        );
      case 'trial_days':
        return Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.timer, color: Colors.blue, size: 20),
        );
      default:
        return Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.settings, color: Colors.grey, size: 20),
        );
    }
  }

  TextInputType _getKeyboardType(String key) {
    switch (key) {
      case 'currency':
        return TextInputType.text;
      default:
        return TextInputType.number;
    }
  }
}