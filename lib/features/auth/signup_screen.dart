import 'package:flutter/material.dart';
import '../../core/auth_service.dart';
import 'teacher_application_screen.dart';
import '../home/home_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String _selectedRole = 'student';
  bool _isLoading = false;

  // ✅ ADD: Level selection for students
List<Map<String, dynamic>> _levels = [];
String? _selectedLevelId;
String? _selectedLevelName;
bool _isLoadingLevels = true;

@override
void initState() {
  super.initState();
  _loadLevels();
}

Future<void> _loadLevels() async {
  try {
    final response = await Supabase.instance.client
        .from('levels')
        .select()
        .order('display_order', ascending: true);

    if (mounted) {
      setState(() {
        _levels = List<Map<String, dynamic>>.from(response);
        _isLoadingLevels = false;
      });
    }
  } catch (_) {
    if (mounted) setState(() => _isLoadingLevels = false);
  }
}

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_selectedRole == 'student' && _selectedLevelId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your class level'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await _authService.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        fullName: _nameController.text.trim(),
        role: _selectedRole,
      );

      // ✅ Save level to profiles for students
      if (_selectedRole == 'student' && _selectedLevelId != null && response.user != null) {
        await Supabase.instance.client
            .from('profiles')
            .update({'level_id': _selectedLevelId})
            .eq('id', response.user!.id);
      }

      if (mounted) {
        if (_selectedRole == 'teacher') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => TeacherApplicationScreen(
                userId: response.user?.id ?? '',
                userEmail: _emailController.text.trim(),
                userName: _nameController.text.trim(),
              ),
            ),
          );
        } else {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => HomeScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Signup failed: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFF1A237E),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Let's get started!",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A237E),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _selectedRole == 'teacher'
                      ? 'Create your teacher account'
                      : 'Create your student account',
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 32),
                
                // Full Name
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) => v!.isEmpty ? 'Enter your full name' : null,
                ),
                const SizedBox(height: 16),
                
                // Email
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) {
                    if (v!.isEmpty) return 'Enter your email';
                    if (!v.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // Password
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) {
                    if (v!.isEmpty) return 'Enter a password';
                    if (v.length < 6) return 'Minimum 6 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // Confirm Password
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) {
                    if (v != _passwordController.text) return 'Passwords do not match';
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                
                // Role Selection
                const Text(
                  'I am a:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _RoleCard(
                        icon: Icons.school,
                        label: 'Student',
                        subtitle: 'Learn from teachers',
                        isSelected: _selectedRole == 'student',
                        onTap: () => setState(() => _selectedRole = 'student'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _RoleCard(
                        icon: Icons.person,
                        label: 'Teacher',
                        subtitle: 'Teach & earn',
                        isSelected: _selectedRole == 'teacher',
                        onTap: () => setState(() => _selectedRole = 'teacher'),
                      ),
                    ),
                  ],
                ),

                // ✅ ADD: Level selection for students
if (_selectedRole == 'student') ...[
  const SizedBox(height: 24),
  const Text('Your Class Level:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
  const SizedBox(height: 4),
  Text('Select the class/level you are in', style: const TextStyle(fontSize: 12, color: Colors.grey)),
  const SizedBox(height: 12),
  DropdownButtonFormField<String>(
    value: _selectedLevelId,
    decoration: InputDecoration(
      labelText: 'Class Level',
      prefixIcon: const Icon(Icons.school_rounded),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    items: _levels.map((level) {
      return DropdownMenuItem<String>(
        value: level['id'] as String,
        child: Text(level['name'] as String),
      );
    }).toList(),
    onChanged: (v) {
      setState(() {
        _selectedLevelId = v;
        _selectedLevelName = _levels.firstWhere((l) => l['id'] == v)['name'] as String?;
      });
    },
    validator: (v) => _selectedRole == 'student' && v == null ? 'Select your class' : null,
  ),
],
                
                if (_selectedRole == 'teacher') ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
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
                            'Teacher accounts require approval. You will fill in your details after signing up.',
                            style: TextStyle(fontSize: 12, color: Colors.amber),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                const SizedBox(height: 32),
                
                // Signup Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _signup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A237E),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Create Account',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Login link
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Already have an account? Log in'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1A237E) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? const Color(0xFF1A237E) : Colors.grey.shade300,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? Colors.white : Colors.grey.shade600, size: 36),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey.shade600,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            )),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(
              color: isSelected ? Colors.white70 : Colors.grey,
              fontSize: 11,
            )),
          ],
        ),
      ),
    );
  }
}