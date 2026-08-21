import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import '../home/home_screen.dart';

class CompleteStudentProfileScreen extends StatefulWidget {
  const CompleteStudentProfileScreen({super.key});

  @override
  State<CompleteStudentProfileScreen> createState() => _CompleteStudentProfileScreenState();
}

class _CompleteStudentProfileScreenState extends State<CompleteStudentProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();

  // Controllers
  final _displayNameController = TextEditingController();
  final _phoneNumberController = TextEditingController();
  final _schoolNameController = TextEditingController();
  
  // Dropdown values
  String? _selectedCountry;
  List<String> _countries = [
    'Zimbabwe',
    'South Africa',
    'Botswana',
    'Zambia',
    'Mozambique',
    'Malawi',
    'Namibia',
    'Other',
  ];

  bool _isSaving = false;
  bool _isLoadingProfile = true;

  @override
  void initState() {
    super.initState();
    _loadExistingProfile();
  }

  Future<void> _loadExistingProfile() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      final profile = await _authService.getProfile();
      
      if (profile != null) {
        _displayNameController.text = profile['display_name'] as String? ?? '';
        _phoneNumberController.text = profile['phone_number'] as String? ?? '';
        _schoolNameController.text = profile['school_name'] as String? ?? '';
        _selectedCountry = profile['country'] as String? ?? 'Zimbabwe';
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    } finally {
      if (mounted) setState(() => _isLoadingProfile = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final userId = _authService.currentUserId;
      if (userId == null) throw Exception('Not logged in');

      // Update profile - make phone number and school name compulsory too
      await Supabase.instance.client
          .from('profiles')
          .update({
            'display_name': _displayNameController.text.trim(),
            'phone_number': _phoneNumberController.text.trim(),
            'school_name': _schoolNameController.text.trim(),
            'country': _selectedCountry ?? 'Zimbabwe',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);

      if (mounted) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile completed successfully! Welcome to AfriNova Academy 🎉'),
            backgroundColor: Color(0xFF4CAF50),
            duration: Duration(seconds: 2),
          ),
        );

        // Navigate to home screen
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => HomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save profile: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _phoneNumberController.dispose();
    _schoolNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent back navigation
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          title: const Text('Complete Your Profile'),
          backgroundColor: Colors.transparent,
          foregroundColor: const Color(0xFF1A237E),
          elevation: 0,
          automaticallyImplyLeading: false, // Remove back button
        ),
        body: _isLoadingProfile
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
            : SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
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
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.person_add_alt_1,
                                  color: Colors.white,
                                  size: 40,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Almost there!',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Please complete your profile to continue',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Required fields notice
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.orange, size: 20),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'All fields are required. This information helps us provide better service.',
                                  style: TextStyle(fontSize: 12, color: Colors.orange),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Display Name
                        const Text(
                          'Display Name *',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A237E),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'This is what teachers and other students will see',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _displayNameController,
                          decoration: InputDecoration(
                            hintText: 'e.g., John D.',
                            prefixIcon: const Icon(Icons.badge_outlined),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.shade200),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF1A237E), width: 2),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Display name is required';
                            }
                            if (v.trim().length < 3) {
                              return 'Display name should be at least 3 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),

                        // Phone Number (Required)
                        const Text(
                          'Phone Number *',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A237E),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'For payment notifications and account recovery',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _phoneNumberController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            hintText: '+263 77 123 4567',
                            prefixIcon: const Icon(Icons.phone_android),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.shade200),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF1A237E), width: 2),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Phone number is required';
                            }
                            final digitsOnly = v.replaceAll(RegExp(r'[^\d]'), '');
                            if (digitsOnly.length < 9) {
                              return 'Enter a valid phone number (at least 9 digits)';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),

                        // School Name (Required)
                        const Text(
                          'School Name *',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A237E),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Your current school or institution',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _schoolNameController,
                          decoration: InputDecoration(
                            hintText: 'e.g., St. Johns High School',
                            prefixIcon: const Icon(Icons.school_outlined),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.shade200),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF1A237E), width: 2),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'School name is required';
                            }
                            if (v.trim().length < 3) {
                              return 'School name should be at least 3 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),

                        // Country (Required)
                        const Text(
                          'Country *',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A237E),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _selectedCountry,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.public),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.shade200),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF1A237E), width: 2),
                            ),
                          ),
                          items: _countries.map((country) {
                            return DropdownMenuItem<String>(
                              value: country,
                              child: Text(country),
                            );
                          }).toList(),
                          onChanged: (v) {
                            setState(() {
                              _selectedCountry = v;
                            });
                          },
                          validator: (v) => v == null ? 'Select your country' : null,
                        ),
                        const SizedBox(height: 32),

                        // Save Button
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _saveProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1A237E),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: _isSaving
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Text(
                                    'Complete Profile & Continue',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}