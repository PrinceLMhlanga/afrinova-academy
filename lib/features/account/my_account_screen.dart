import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/auth_service.dart';
import '../auth/welcome_screen.dart';

class MyAccountScreen extends StatefulWidget {
  const MyAccountScreen({super.key});

  @override
  State<MyAccountScreen> createState() => _MyAccountScreenState();
}

class _MyAccountScreenState extends State<MyAccountScreen> {
  final AuthService _authService = AuthService();
  
  // Text controllers for profile fields
  final _fullNameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _schoolNameController = TextEditingController();
  final _countryController = TextEditingController();
  final _avatarUrlController = TextEditingController();
  
  // Password controllers
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  // State variables
  Map<String, dynamic>? _profile;
  String _role = 'student';
  String _approvalStatus = 'pending';
  String _subscriptionPlan = 'free';
  bool _isSubscribed = false;
  String? _levelId;
  String? _levelName;
  DateTime? _subscriptionExpiresAt;
  DateTime? _createdAt;
  
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isChangingPassword = false;
  bool _showPasswordSection = false;
  
  // Password visibility toggles
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  
  // Available levels (you should fetch these from your database)
  List<Map<String, dynamic>> _levels = [];
  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      // ✅ Load levels from database
      final levelsResponse = await Supabase.instance.client
          .from('levels')
          .select()
          .order('display_order', ascending: true);
      
      if (mounted) {
        setState(() => _levels = List<Map<String, dynamic>>.from(levelsResponse));
      }

      // Load profile
      final profile = await _authService.getProfile();
      if (profile != null && mounted) {
        setState(() {
          _profile = profile;
          _role = profile['role'] ?? 'student';
          _approvalStatus = profile['approval_status'] ?? 'pending';
          _subscriptionPlan = profile['subscription_plan'] ?? 'free';
          _isSubscribed = profile['is_subscribed'] ?? false;
          _levelId = profile['level_id'] as String?;
          _subscriptionExpiresAt = profile['subscription_expires_at'] != null 
              ? DateTime.parse(profile['subscription_expires_at']) 
              : null;
          _createdAt = profile['created_at'] != null 
              ? DateTime.parse(profile['created_at']) 
              : null;
          
          // ✅ Get level name from loaded levels
          if (_levelId != null) {
            final level = _levels.firstWhere(
              (l) => l['id'] == _levelId,
              orElse: () => {'name': 'Not set'},
            );
            _levelName = level['name'] as String?;
          }
          
          _fullNameController.text = profile['full_name'] ?? '';
          _displayNameController.text = profile['display_name'] ?? profile['full_name'] ?? '';
          _emailController.text = profile['email'] ?? '';
          _phoneController.text = profile['phone_number'] ?? '';
          _schoolNameController.text = profile['school_name'] ?? '';
          _countryController.text = profile['country'] ?? '';
          _avatarUrlController.text = profile['avatar_url'] ?? '';
          
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      // Update email in Auth if changed
      final currentEmail = _profile?['email'] ?? '';
      final newEmail = _emailController.text.trim();
      
      if (newEmail != currentEmail && newEmail.isNotEmpty) {
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(email: newEmail),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Verification email sent to your new email address.'),
              backgroundColor: Color(0xFFFF9800),
              duration: Duration(seconds: 5),
            ),
          );
        }
      }

      // Update profile in database
      final Map<String, dynamic> updates = {
        'full_name': _fullNameController.text.trim(),
        'display_name': _displayNameController.text.trim(),
        'phone_number': _phoneController.text.trim(),
        'school_name': _schoolNameController.text.trim(),
        'country': _countryController.text.trim(),
        'avatar_url': _avatarUrlController.text.trim(),
        'email': newEmail,
        'level_id': _levelId,
        'updated_at': DateTime.now().toIso8601String(),
      };

      await Supabase.instance.client.from('profiles').update(updates).eq('id', userId);

      if (mounted) {
        setState(() {
          _profile?.addAll(updates);
          // Update level name
          if (_levelId != null) {
  final level = _levels.firstWhere(
    (l) => l['id'] == _levelId,
    orElse: () => {'name': 'Not set'},
  );
  _levelName = level['name'] as String?;
}
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully! ✅'),
            backgroundColor: Color(0xFF4CAF50),
          ),
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

  Future<void> _changePassword() async {
    if (_currentPasswordController.text.isEmpty) {
      _showError('Please enter your current password');
      return;
    }
    if (_newPasswordController.text.isEmpty) {
      _showError('Please enter a new password');
      return;
    }
    if (_newPasswordController.text.length < 6) {
      _showError('Password must be at least 6 characters');
      return;
    }
    if (_newPasswordController.text != _confirmPasswordController.text) {
      _showError('New passwords do not match');
      return;
    }

    setState(() => _isChangingPassword = true);
    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser?.email == null) {
        throw Exception('No authenticated user found');
      }

      await Supabase.instance.client.auth.signInWithPassword(
        email: currentUser!.email!,
        password: _currentPasswordController.text,
      );

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _newPasswordController.text),
      );

      if (mounted) {
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        setState(() => _showPasswordSection = false);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password changed successfully! 🔒'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Failed to change password';
        if (e.toString().contains('invalid')) {
          errorMessage = 'Current password is incorrect';
        }
        _showError(errorMessage);
      }
    } finally {
      if (mounted) setState(() => _isChangingPassword = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout?'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _authService.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _displayNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _schoolNameController.dispose();
    _countryController.dispose();
    _avatarUrlController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
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
              expandedHeight: 140,
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
                  title: Row(
                    children: [
                      Text('👤', style: TextStyle(fontSize: 24)),
                      SizedBox(width: 8),
                      Text('My Account',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          )),
                    ],
                  ),
                  centerTitle: false,
                  titlePadding: EdgeInsets.only(left: 16, bottom: 16),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (_isLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(60),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else ...[
                    _buildProfileCard(),
                    const SizedBox(height: 24),
                    _buildEditForm(),
                    const SizedBox(height: 16),
                    
                    // Show subscription info only for students
                    if (_role == 'student') ...[
                      _buildSubscriptionInfo(),
                      const SizedBox(height: 16),
                    ],
                    
                    // Show approval status only for teachers
                    if (_role == 'teacher') ...[
                      _buildApprovalStatus(),
                      const SizedBox(height: 16),
                    ],
                    
                    _buildPasswordSection(),
                    const SizedBox(height: 16),
                    _buildAccountActions(),
                    const SizedBox(height: 16),
                    _buildAppInfo(),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 10)],
      ),
      child: Column(children: [
        Stack(
          children: [
            CircleAvatar(
              radius: 50,
              backgroundColor: const Color(0xFF1A237E).withOpacity(0.1),
              backgroundImage: _avatarUrlController.text.isNotEmpty 
                  ? NetworkImage(_avatarUrlController.text) 
                  : null,
              child: _avatarUrlController.text.isEmpty
                  ? Text(
                      (_displayNameController.text.isNotEmpty 
                          ? _displayNameController.text[0] 
                          : 'U').toUpperCase(),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A237E),
                      ),
                    )
                  : null,
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: GestureDetector(
                onTap: _showAvatarUrlDialog,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A237E),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _displayNameController.text.isNotEmpty 
              ? _displayNameController.text 
              : _fullNameController.text,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A237E),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _emailController.text,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _getRoleColor().withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _role.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _getRoleColor(),
                ),
              ),
            ),
            if (_role == 'teacher') ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _getApprovalStatusColor().withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _approvalStatus.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _getApprovalStatusColor(),
                  ),
                ),
              ),
            ],
            if (_role == 'student' && _levelName != null) ...[
  const SizedBox(width: 8),
  Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(
      color: _getLevelColor(_levelName!).withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      _levelName!,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: _getLevelColor(_levelName!),
      ),
    ),
  ),
],
          ],
        ),
        if (_role == 'student' && _isSubscribed) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star, size: 14, color: Colors.green.shade700),
                const SizedBox(width: 4),
                Text(
                  'Premium Member',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ]),
    );
  }

  Color _getRoleColor() {
    switch (_role) {
      case 'teacher': return const Color(0xFF4CAF50);
      case 'admin': return const Color(0xFFFF9800);
      default: return const Color(0xFF1A237E);
    }
  }

  Color _getApprovalStatusColor() {
    switch (_approvalStatus) {
      case 'approved': return const Color(0xFF4CAF50);
      case 'rejected': return Colors.red;
      default: return const Color(0xFFFF9800);
    }
  }

  void _showAvatarUrlDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Avatar'),
        content: TextField(
          controller: _avatarUrlController,
          decoration: const InputDecoration(
            labelText: 'Avatar URL',
            hintText: 'Enter image URL',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {});
              Navigator.pop(ctx);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Widget _buildEditForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Edit Profile',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A237E),
              )),
          const SizedBox(height: 16),
          
          TextFormField(
            controller: _fullNameController,
            decoration: InputDecoration(
              labelText: 'Full Name',
              prefixIcon: const Icon(Icons.person_outline),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              helperText: _role == 'teacher' 
                  ? 'Your real name (hidden from students)' 
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          
          TextFormField(
            controller: _displayNameController,
            decoration: InputDecoration(
              labelText: 'Display Name',
              prefixIcon: const Icon(Icons.badge_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              helperText: _role == 'teacher' 
                  ? 'Name shown to students (e.g., Mr. Smith)' 
                  : 'Name shown to others',
              helperStyle: TextStyle(
                fontSize: 11, 
                color: _role == 'teacher' ? Colors.blue.shade700 : Colors.grey,
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Email Address',
              prefixIcon: const Icon(Icons.email_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              helperText: 'Changing email requires verification',
              helperStyle: TextStyle(fontSize: 11, color: Colors.orange.shade700),
            ),
          ),
          const SizedBox(height: 12),
          
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Phone Number',
              prefixIcon: const Icon(Icons.phone_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          
          TextFormField(
            controller: _schoolNameController,
            decoration: InputDecoration(
              labelText: 'School/Institution',
              prefixIcon: const Icon(Icons.school_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          
          TextFormField(
            controller: _countryController,
            decoration: InputDecoration(
              labelText: 'Country',
              prefixIcon: const Icon(Icons.public_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          
          // Level selector for students
if (_role == 'student') ...[
  const SizedBox(height: 12),
  DropdownButtonFormField<String>(
    value: _levelId,
    decoration: InputDecoration(
      labelText: 'Your Level',
      prefixIcon: const Icon(Icons.school_rounded),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    items: _levels.map((level) {
      return DropdownMenuItem<String>(
        value: level['id'] as String,
        child: Text(level['name'] as String? ?? 'Unknown'),
      );
    }).toList(),
    onChanged: (value) {
      setState(() {
        _levelId = value;
        if (value != null) {
          final level = _levels.firstWhere(
            (l) => l['id'] == value,
            orElse: () => {'name': 'Unknown'},
          );
          _levelName = level['name'] as String?;
        }
      });
    },
  ),
],
          
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveProfile,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save),
              label: const Text('Save Changes'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A237E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionInfo() {
    // ✅ Check if subscription is actually active (not expired)
    bool isSubscriptionActive = _isSubscribed && 
        _subscriptionExpiresAt != null && 
        _subscriptionExpiresAt!.isAfter(DateTime.now());
    
    // Check if trial is active
    bool isTrialActive = !_isSubscribed && 
        _subscriptionExpiresAt != null && 
        _subscriptionExpiresAt!.isAfter(DateTime.now());
    
    bool isExpired = _isSubscribed && 
        _subscriptionExpiresAt != null && 
        _subscriptionExpiresAt!.isBefore(DateTime.now());
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isSubscriptionActive ? Icons.star : Icons.star_outline,
                color: isSubscriptionActive ? Colors.amber : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                isSubscriptionActive 
                    ? 'Premium Subscription' 
                    : isTrialActive 
                        ? 'Trial Active'
                        : isExpired 
                            ? 'Subscription Expired'
                            : 'Free Account',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A237E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          if (isSubscriptionActive) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Active Subscription',
                            style: TextStyle(fontWeight: FontWeight.w600, color: Colors.green.shade700)),
                        if (_subscriptionExpiresAt != null)
                          Text('Expires: ${_formatDate(_subscriptionExpiresAt!)}',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else if (isTrialActive) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.rocket, color: Colors.orange.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Trial Period',
                            style: TextStyle(fontWeight: FontWeight.w600, color: Colors.orange.shade700)),
                        Text('Expires: ${_formatDate(_subscriptionExpiresAt!)}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else if (isExpired) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.red.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Subscription Expired',
                            style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red.shade700)),
                        Text('Expired: ${_formatDate(_subscriptionExpiresAt!)}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('Upgrade to premium for access to all courses and features',
                        style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
          
          // Show upgrade button if not subscribed or expired
          if (!isSubscriptionActive || isExpired) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  // Navigate to subscription page
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1A237E),
                  side: const BorderSide(color: Color(0xFF1A237E)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(isExpired ? 'Renew Subscription' : 'Upgrade to Premium'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildApprovalStatus() {
    String statusMessage = '';
    Color statusColor = Colors.grey;
    IconData statusIcon = Icons.pending;
    
    switch (_approvalStatus) {
      case 'approved':
        statusMessage = '✅ Your teacher account is approved! You can now create and manage courses.';
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'rejected':
        statusMessage = '❌ Your application was rejected. Please contact support for assistance.';
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      default:
        statusMessage = '⏳ Your application is pending review. You\'ll be notified once approved.';
        statusColor = Colors.orange;
        statusIcon = Icons.pending;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_user, color: Color(0xFF1A237E)),
              SizedBox(width: 8),
              Text('Teacher Status',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A237E),
                  )),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: statusColor.withOpacity(0.3)),
            ),
            child: Text(
              statusMessage,
              style: TextStyle(
                fontSize: 13,
                color: statusColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day} ${_getMonthName(date.month)} ${date.year}';
  }

  String _getMonthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }

  Widget _buildPasswordSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              setState(() => _showPasswordSection = !_showPasswordSection);
            },
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A237E).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.lock_outline, color: Color(0xFF1A237E)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Change Password',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A237E),
                          )),
                      Text('Update your account password',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _showPasswordSection ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.chevron_right, color: Colors.grey),
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: [
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _currentPasswordController,
                  obscureText: _obscureCurrentPassword,
                  decoration: InputDecoration(
                    labelText: 'Current Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureCurrentPassword ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() => _obscureCurrentPassword = !_obscureCurrentPassword);
                      },
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _newPasswordController,
                  obscureText: _obscureNewPassword,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureNewPassword ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() => _obscureNewPassword = !_obscureNewPassword);
                      },
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    helperText: 'Minimum 6 characters',
                    helperStyle: const TextStyle(fontSize: 11),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: InputDecoration(
                    labelText: 'Confirm New Password',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
                      },
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _isChangingPassword ? null : _changePassword,
                    icon: _isChangingPassword
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.lock_reset),
                    label: const Text('Update Password'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            crossFadeState: _showPasswordSection
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountActions() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Account',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A237E),
            )),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.logout, color: Colors.red),
          ),
          title: const Text('Logout', style: TextStyle(fontWeight: FontWeight.w500)),
          subtitle: const Text('Sign out of your account',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
          onTap: _logout,
        ),
        if (_createdAt != null) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 8),
                Text(
                  'Member since ${_formatDate(_createdAt!)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ]),
    );
  }

  Widget _buildAppInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.04), blurRadius: 6)],
      ),
      child: Column(children: [
        Text('AfriNova Academy',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            )),
        const SizedBox(height: 4),
        Text('Smart learning for the next generation',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
      ]),
    );
  }
  Color _getLevelColor(String level) {
  switch (level) {
    case 'Form 1': return Colors.blue;
    case 'Form 2': return Colors.teal;
    case 'O-Level': return const Color(0xFFFF9800);
    case 'A-Level': return Colors.purple;
    default: return Colors.grey;
  }
}
}