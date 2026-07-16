import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';

class TeacherPricingScreen extends StatefulWidget {
  const TeacherPricingScreen({super.key});

  @override
  State<TeacherPricingScreen> createState() => _TeacherPricingScreenState();
}

class _TeacherPricingScreenState extends State<TeacherPricingScreen> {
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _plans = [];
  bool _isLoading = true;
  bool _showForm = false;

  List<Map<String, dynamic>> _levels = [];
List<Map<String, dynamic>> _subjects = [];
String? _selectedLevelId;
String? _selectedSubjectId;

  // Form controllers
  final _planNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _monthlyPriceController = TextEditingController();
  final _termlyPriceController = TextEditingController();
  final _durationController = TextEditingController(text: '30');
  
  // Features
  final List<String> _availableFeatures = [
    'Live Lessons',
    'Recorded Lessons',
    'Notes & Resources',
    'Exam Preparation',
    'MCQ Practice',
    'One-on-One Support',
    'Homework Help',
    'Progress Reports',
  ];
  List<String> _selectedFeatures = [];

  // Editing
  String? _editingPlanId;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadPlans();
    _loadDropdownData();
  }

  Future<void> _loadDropdownData() async {
  try {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    // Load teacher's levels
    final levelsResponse = await Supabase.instance.client
        .from('teacher_levels')
        .select('level_id, levels!inner(name)')
        .eq('teacher_id', userId);

    // Load teacher's subjects
    final subjectsResponse = await Supabase.instance.client
        .from('teacher_subjects')
        .select('subject_id, subjects!inner(name)')
        .eq('teacher_id', userId);

    if (mounted) {
      setState(() {
        _levels = List<Map<String, dynamic>>.from(levelsResponse);
        _subjects = List<Map<String, dynamic>>.from(subjectsResponse);
      });
    }
  } catch (e) {
    debugPrint('Error loading dropdown data: $e');
  }
}

  Future<void> _loadPlans() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      final response = await Supabase.instance.client
          .from('teacher_pricing')
          .select()
          .eq('teacher_id', userId)
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _plans = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading plans: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _savePlan() async {
    if (_planNameController.text.isEmpty) return;
    if (_monthlyPriceController.text.isEmpty && _termlyPriceController.text.isEmpty) return;

    setState(() => _isSaving = true);

    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      final planData = {
        'teacher_id': userId,
        'plan_name': _planNameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'price_monthly': double.tryParse(_monthlyPriceController.text) ?? 0,
        'price_termly': double.tryParse(_termlyPriceController.text) ?? 0,
        'duration_days': int.tryParse(_durationController.text) ?? 30,
        'features': _selectedFeatures,
        'level_id': _selectedLevelId,     // ✅ Add
        'subject_id': _selectedSubjectId, // ✅ Add
        'is_active': true,
      };

      if (_editingPlanId != null) {
        planData['updated_at'] = DateTime.now().toIso8601String();
        await Supabase.instance.client
            .from('teacher_pricing')
            .update(planData)
            .eq('id', _editingPlanId!);
      } else {
        await Supabase.instance.client
            .from('teacher_pricing')
            .insert(planData);
      }

      _resetForm();
      _loadPlans();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_editingPlanId != null ? 'Plan updated! ✅' : 'Plan created! ✅'),
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
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _editPlan(Map<String, dynamic> plan) {
    setState(() {
      _editingPlanId = plan['id'] as String;
      _planNameController.text = plan['plan_name'] ?? '';
      _descriptionController.text = plan['description'] ?? '';
      _monthlyPriceController.text = plan['price_monthly']?.toString() ?? '';
      _termlyPriceController.text = plan['price_termly']?.toString() ?? '';
      _durationController.text = plan['duration_days']?.toString() ?? '30';
      _selectedFeatures = List<String>.from(plan['features'] ?? []);
      _selectedLevelId = plan['level_id'] as String?;      // ✅
      _selectedSubjectId = plan['subject_id'] as String?;  // ✅
      _showForm = true;
    });
  }

  void _resetForm() {
    _planNameController.clear();
    _descriptionController.clear();
    _monthlyPriceController.clear();
    _termlyPriceController.clear();
    _durationController.text = '30';
    _selectedFeatures = [];
    _selectedSubjectId = null;   // ✅
    _selectedLevelId = null;      // ✅
    _editingPlanId = null;
    _showForm = false;
  }

  Future<void> _deletePlan(String planId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Plan?'),
        content: const Text('Students on this plan will be affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await Supabase.instance.client.from('teacher_pricing').delete().eq('id', planId);
      _loadPlans();
    }
  }

  String _getLevelName(String? levelId) {
  if (levelId == null) return '';
  final level = _levels.firstWhere(
    (l) => l['level_id'] == levelId,
    orElse: () => {'levels': {'name': ''}},
  );
  return (level['levels'] as Map)['name'] ?? '';
}

String _getSubjectName(String? subjectId) {
  if (subjectId == null) return '';
  final subject = _subjects.firstWhere(
    (s) => s['subject_id'] == subjectId,
    orElse: () => {'subjects': {'name': ''}},
  );
  return (subject['subjects'] as Map)['name'] ?? '';
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

  @override
  void dispose() {
    _planNameController.dispose();
    _descriptionController.dispose();
    _monthlyPriceController.dispose();
    _termlyPriceController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Pricing Plans'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          if (!_showForm)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => setState(() => _showForm = true),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A237E).withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF1A237E).withOpacity(0.1)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Color(0xFF1A237E), size: 18),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Create custom pricing plans for your students. If no plan is set, platform default pricing applies.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF1A237E)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Plans list
                  if (_plans.isEmpty && !_showForm)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          children: [
                            Icon(Icons.price_change_outlined, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            const Text('No custom plans yet', style: TextStyle(color: Colors.grey, fontSize: 16)),
                            const SizedBox(height: 4),
                            const Text('Using platform default pricing (\$10/mo, \$25/term)',
                                style: TextStyle(color: Colors.grey, fontSize: 13)),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: () => setState(() => _showForm = true),
                              icon: const Icon(Icons.add),
                              label: const Text('Create Your First Plan'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1A237E),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Show existing plans
                  ..._plans.map((plan) => _buildPlanCard(plan)),

                  const SizedBox(height: 16),

                  // Add/Edit form
                  if (_showForm) _buildPlanForm(),
                ],
              ),
            ),
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan) {
    final features = List<String>.from(plan['features'] ?? []);
    final monthly = (plan['price_monthly'] as num?)?.toDouble() ?? 0;
    final termly = (plan['price_termly'] as num?)?.toDouble() ?? 0;
    final isDefault = plan['is_default'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDefault ? const Color(0xFF4CAF50).withOpacity(0.4) : Colors.grey.shade200,
          width: isDefault ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(plan['plan_name'] ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    if (isDefault) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Default', style: TextStyle(fontSize: 10, color: Color(0xFF4CAF50), fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ]),
                ]),
              ),
              PopupMenuButton<String>(
                itemBuilder: (ctx) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                ],
                onSelected: (action) {
                  if (action == 'edit') _editPlan(plan);
                  if (action == 'delete') _deletePlan(plan['id'] as String);
                },
              ),
            ],
          ),
          // In _buildPlanCard, after plan name:
if (plan['level_id'] != null || plan['subject_id'] != null) ...[
  const SizedBox(height: 6),
  Row(
    children: [
      if (plan['level_id'] != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _getLevelColor(_getLevelName(plan['level_id'])).withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(_getLevelName(plan['level_id']),
              style: TextStyle(fontSize: 10, color: _getLevelColor(_getLevelName(plan['level_id'])))),
        ),
      if (plan['level_id'] != null && plan['subject_id'] != null) const SizedBox(width: 6),
      if (plan['subject_id'] != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF1A237E).withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(_getSubjectName(plan['subject_id']),
              style: const TextStyle(fontSize: 10, color: Color(0xFF1A237E))),
        ),
    ],
  ),
],
          if (plan['description']?.toString().isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(plan['description'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ],
          const SizedBox(height: 12),

          // Pricing
          Row(
            children: [
              if (monthly > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A237E).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF1A237E).withOpacity(0.1)),
                  ),
                  child: Column(
                    children: [
                      Text('\$${monthly.toStringAsFixed(0)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                      const Text('/month', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
              if (monthly > 0 && termly > 0) const SizedBox(width: 12),
              if (termly > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.2)),
                  ),
                  child: Column(
                    children: [
                      Text('\$${termly.toStringAsFixed(0)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF4CAF50))),
                      const Text('/term', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Features
          if (features.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: features.map((f) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.check, size: 12, color: Color(0xFF4CAF50)),
                  const SizedBox(width: 4),
                  Text(f, style: const TextStyle(fontSize: 11)),
                ]),
              )).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildPlanForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.3)),
        boxShadow: [BoxShadow(color: const Color(0xFF4CAF50).withOpacity(0.08), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(_editingPlanId != null ? 'Edit Plan' : 'New Plan', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton(onPressed: _resetForm, child: const Text('Cancel')),
          ]),
          const SizedBox(height: 16),

          TextFormField(
  controller: _planNameController,
  decoration: InputDecoration(
    labelText: 'Plan Name',
    hintText: 'e.g., Premium Physics Access',
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  ),
),
const SizedBox(height: 12),

// ✅ Level + Subject row
Row(
  children: [
    Expanded(
      child: DropdownButtonFormField<String>(
        value: _selectedLevelId,
        decoration: InputDecoration(
          labelText: 'Level',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          isDense: true,
        ),
        items: [
          const DropdownMenuItem<String>(value: null, child: Text('All Levels', style: TextStyle(fontSize: 13))),
          ..._levels.map((l) {
            final level = l['levels'] as Map<String, dynamic>;
            return DropdownMenuItem<String>(
              value: l['level_id'] as String,
              child: Text(level['name'] ?? '', style: const TextStyle(fontSize: 13)),
            );
          }),
        ],
        onChanged: (v) => setState(() => _selectedLevelId = v),
      ),
    ),
    const SizedBox(width: 10),
    Expanded(
      child: DropdownButtonFormField<String>(
        value: _selectedSubjectId,
        decoration: InputDecoration(
          labelText: 'Subject',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          isDense: true,
        ),
        items: [
          const DropdownMenuItem<String>(value: null, child: Text('All Subjects', style: TextStyle(fontSize: 13))),
          ..._subjects.map((s) {
            final subject = s['subjects'] as Map<String, dynamic>;
            return DropdownMenuItem<String>(
              value: s['subject_id'] as String,
              child: Text(subject['name'] ?? '', style: const TextStyle(fontSize: 13)),
            );
          }),
        ],
        onChanged: (v) => setState(() => _selectedSubjectId = v),
      ),
    ),
  ],
),
          const SizedBox(height: 12),

          TextFormField(
            controller: _descriptionController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Description',
              hintText: 'What does this plan include?',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),

          // Pricing
          const Text('Pricing (leave blank if not offering)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _monthlyPriceController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Monthly (\$)',
                    prefixText: '\$ ',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _termlyPriceController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Termly (\$)',
                    prefixText: '\$ ',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Features
          const Text('Features Included', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _availableFeatures.map((feature) {
              final isSelected = _selectedFeatures.contains(feature);
              return FilterChip(
                label: Text(feature, style: const TextStyle(fontSize: 11)),
                selected: isSelected,
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      _selectedFeatures.add(feature);
                    } else {
                      _selectedFeatures.remove(feature);
                    }
                  });
                },
                selectedColor: const Color(0xFF4CAF50).withOpacity(0.2),
                checkmarkColor: const Color(0xFF4CAF50),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // Save
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _savePlan,
              icon: _isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
              label: Text(_editingPlanId != null ? 'Update Plan' : 'Create Plan'),
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
}