import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import '../../core/referral_service.dart';

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  final AuthService _authService = AuthService();
  final ReferralService _referralService = ReferralService();
  
  String? _referralCode;
  Map<String, dynamic>? _stats;
  bool _isLoading = true;
  bool _isGenerating = false;

  String _userRole = 'student';

  @override
  void initState() {
    super.initState();
    _loadReferralData();
  }

  Future<void> _loadReferralData() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      final profile = await _authService.getProfile();
    _userRole = profile?['role'] as String? ?? 'student';

      // Get existing codes
      final codes = await _referralService.getUserReferralCodes(userId);
      
      if (codes.isNotEmpty) {
        _referralCode = codes.first['code'] as String;
      }

      // Get stats
      final stats = await _referralService.getReferralStats(userId);
      
      if (mounted) {
        setState(() {
          _stats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading referral data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _generateCode() async {
    setState(() => _isGenerating = true);
    
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      final code = await _referralService.generateReferralCode(
      userId,
      referrerRole: _userRole, // ✅ Pass role
    );
      
      setState(() {
        _referralCode = code;
        _isGenerating = false;
      });
      
      // Reload stats
      await _loadReferralData();
    } catch (e) {
      debugPrint('Error generating code: $e');
      if (mounted) setState(() => _isGenerating = false);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate code: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _copyLink() async {
    if (_referralCode == null) return;
    
    final link = _referralService.getReferralLink(_referralCode!);
    await Clipboard.setData(ClipboardData(text: link));
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Link copied to clipboard! ✅'),
          backgroundColor: Color(0xFF4CAF50),
        ),
      );
    }
  }

  Future<void> _shareLink() async {
    if (_referralCode == null) return;
    
    final userId = _authService.currentUserId;
    String userName = 'your friend';
    
    if (userId != null) {
      final profile = await _authService.getProfile();
      userName = profile?['display_name'] ?? profile?['full_name'] ?? 'your friend';
    }
    
    await _referralService.shareReferralLink(_referralCode!, userName);
  }

  // In ReferralScreen, update the header message based on role:
String _getHeaderMessage() {
  switch (_userRole) {
    case 'teacher':
      return 'Refer Students, Earn \$2 Each!';
    case 'admin':
      return 'Refer Students, Earn \$2 Each!';
    default:
      return 'Refer Friends, Earn Rewards!';
  }
}

String _getSubtitleMessage() {
  switch (_userRole) {
    case 'teacher':
      return 'Get \$2 for every student who subscribes to AI Premium using your link!';
    case 'admin':
      return 'Get \$2 for every student who subscribes to AI Premium using your link!';
    default:
      return 'Get 5 friends to subscribe and get FREE AI access for a month!';
  }
}

@override
Widget build(BuildContext context) {
  final isTeacher = _userRole == 'teacher' || _userRole == 'admin';
  // ✅ Check if stats is null first
  final successfulReferrals = int.tryParse(_stats?['successful_referrals']?.toString() ?? '0') ?? 0;
  final rewardsEarned = int.tryParse(_stats?['rewards_earned']?.toString() ?? '0') ?? 0;
  final progressToNext = (successfulReferrals % 5) / 5;

  return Scaffold(
    appBar: AppBar(
      title: const Text('Refer & Earn'),
      backgroundColor: const Color(0xFF1A237E),
      foregroundColor: Colors.white,
    ),
    body: _isLoading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
        : RefreshIndicator(
            onRefresh: _loadReferralData,
            color: const Color(0xFF1A237E),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header card
                 Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A237E), Color(0xFF283593)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            isTeacher ? Icons.payments : Icons.card_giftcard,
            color: Colors.white,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            _getHeaderMessage(),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _getSubtitleMessage(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    ),
                  const SizedBox(height: 24),

                  // Referral link section
                  if (_referralCode != null) ...[
                    const Text(
                      'Your Referral Link',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _referralService.getReferralLink(_referralCode!),
                                  style: const TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy, color: Color(0xFF1A237E)),
                                onPressed: _copyLink,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _shareLink,
                              icon: const Icon(Icons.share),
                              label: const Text('Share Link'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1A237E),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else
                    Center(
                      child: ElevatedButton.icon(
                        onPressed: _isGenerating ? null : _generateCode,
                        icon: _isGenerating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.add),
                        label: const Text('Generate Referral Code'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A237E),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),

                  // ✅ Stats section - Only show if stats is not null
                  if (_stats != null) ...[
                    const Text(
                      'Your Referral Progress',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    
                    // Row 1: Total Referrals + Registered
                    Row(
                      children: [
                        _buildStatCard(
                          'Total Referrals',
                          _stats!['total_referrals']?.toString() ?? '0',
                          Icons.people,
                          Colors.blue,
                        ),
                        const SizedBox(width: 12),
                        _buildStatCard(
                          'Registered',
                          _stats!['registered_referrals']?.toString() ?? '0',
                          Icons.person_add_alt,
                          Colors.indigo,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // Row 2: In Trial + Subscribed
                    Row(
                      children: [
                        _buildStatCard(
                          'In Trial',
                          _stats!['trial_referrals']?.toString() ?? '0',
                          Icons.timer,
                          Colors.orange,
                        ),
                        const SizedBox(width: 12),
                        _buildStatCard(
                          'Subscribed',
                          _stats!['successful_referrals']?.toString() ?? '0',
                          Icons.check_circle,
                          Colors.green,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // Row 3: Rewards Earned + Claimed
                   Row(
                      children: [
                        if (isTeacher) ...[
                          _buildStatCard(
                            'Total Earned',
                            '\$${(rewardsEarned * 2).toStringAsFixed(2)}',
                            Icons.payments,
                            Colors.green,
                          ),
                        ] else ...[
                          _buildStatCard(
                            'Rewards Earned',
                            _stats!['rewards_earned']?.toString() ?? '0',
                            Icons.card_giftcard,
                            Colors.purple,
                          ),
                          const SizedBox(width: 12),
                          _buildStatCard(
                            'Days of Free AI',
                            (rewardsEarned * 30).toString(),
                            Icons.calendar_month_rounded,
                            Colors.green,
                          ),
                        ],
                      ],
                    ),
                    if (!isTeacher) ...[
                    const SizedBox(height: 24),
                    
                    // Progress to next reward
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Progress to Free AI Month',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: progressToNext.clamp(0.0, 1.0),
                            backgroundColor: Colors.grey.shade200,
                            color: const Color(0xFF4CAF50),
                            minHeight: 8,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$successfulReferrals successful referrals • $rewardsEarned rewards earned',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          Text(
                            '${5 - (successfulReferrals % 5)} more referrals for next reward',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    ]
                  ],
                ],
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
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}