import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import '../../core/ai_service.dart';
import 'availability_setup_screen.dart';

class StudyPlanScreen extends StatefulWidget {
  const StudyPlanScreen({super.key});

  @override
  State<StudyPlanScreen> createState() => _StudyPlanScreenState();
}

class _StudyPlanScreenState extends State<StudyPlanScreen> {
  final AuthService _authService = AuthService();
  final AIService _aiService = AIService();
  
  Map<String, dynamic>? _weeklyPlan;
  bool _isLoading = true;
  bool _isGenerating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrGeneratePlan();
  }

  String _getWeekStartDate() {
    final now = DateTime.now();
    final day = now.weekday;
    final monday = now.subtract(Duration(days: day - 1));
    return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadOrGeneratePlan() async {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    setState(() => _isLoading = true);

    try {
      final hasAvailability = await _checkAvailability(userId);
    
    if (!hasAvailability) {
      // Redirect to availability setup
      if (mounted) {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AvailabilitySetupScreen()),
        );
        if (result == true) {
          // Reload after setting availability
          _loadOrGeneratePlan();
        } else {
          setState(() => _isLoading = false);
        }
      }
      return;
    }
      final weekStart = _getWeekStartDate();

      // Check if plan already exists for this week
      final existing = await Supabase.instance.client
          .from('study_plans')
          .select('ai_analysis, created_at')
          .eq('student_id', userId)
          .eq('week_start_date', weekStart)
          .maybeSingle();

      if (existing != null) {
        // Use existing plan
        setState(() {
          _weeklyPlan = existing['ai_analysis'] as Map<String, dynamic>?;
          _isLoading = false;
        });
      } else {
        // Generate new plan
        setState(() => _isGenerating = true);
        await _generatePlan(userId);
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load study plan';
        _isLoading = false;
      });
    }
  }

  Future<bool> _checkAvailability(String userId) async {
  try {
    final data = await Supabase.instance.client
        .from('student_availability')
        .select('id')
        .eq('student_id', userId)
        .maybeSingle();
    return data != null;
  } catch (e) {
    return false;
  }
}

  Future<void> _generatePlan(String userId) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'ai-tutor',
        body: {
          'action': 'generate_study_plan',
          'studentId': userId,
        },
      );

      final plan = response.data as Map<String, dynamic>?;

      if (mounted) {
        setState(() {
          _weeklyPlan = plan;
          _isLoading = false;
          _isGenerating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to generate plan';
          _isLoading = false;
          _isGenerating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('My Study Plan'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: _isLoading || _isGenerating
          ? _buildSkeletonLoader()
          : _error != null
              ? _buildErrorState()
              : _weeklyPlan == null
                  ? _buildEmptyState()
                  : _buildPlanView(),
    );
  }

  Widget _buildSkeletonLoader() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildShimmerCard(height: 120),
        const SizedBox(height: 16),
        _buildShimmerCard(height: 80),
        const SizedBox(height: 16),
        ...List.generate(5, (i) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildShimmerCard(height: 100),
        )),
      ],
    );
  }

  Widget _buildShimmerCard({double height = 100}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.error_outline, size: 48, color: Colors.red),
        const SizedBox(height: 16),
        Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 16)),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: _loadOrGeneratePlan, child: const Text('Retry')),
      ]),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.auto_awesome, size: 48, color: Color(0xFF1A237E)),
        const SizedBox(height: 16),
        const Text('Generating your study plan...', style: TextStyle(fontSize: 16)),
        const SizedBox(height: 8),
        const Text('This may take a few moments', style: TextStyle(color: Colors.grey, fontSize: 13)),
      ]),
    );
  }

  Widget _buildPlanView() {
    final plan = _weeklyPlan!;
    final strengths = plan['strengths'] as List? ?? [];
    final weaknesses = plan['weaknesses'] as List? ?? [];
    final weeklyPlan = plan['weekly_plan'] as Map<String, dynamic>? ?? {};
    final insights = plan['insights'] as String? ?? '';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Strengths & Weaknesses card
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.trending_up, color: Color(0xFF4CAF50), size: 18),
                    SizedBox(width: 6),
                    Text('Strengths', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4CAF50))),
                  ]),
                  const SizedBox(height: 8),
                  ...strengths.take(3).map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• ${s['topic'] ?? s['subject']} (${s['score']}%)', style: const TextStyle(fontSize: 12)),
                  )),
                ]),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.priority_high, color: Colors.orange, size: 18),
                    SizedBox(width: 6),
                    Text('To Improve', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                  ]),
                  const SizedBox(height: 8),
                  ...weaknesses.take(3).map((w) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• ${w['topic'] ?? w['subject']} (${w['score']}%)', style: const TextStyle(fontSize: 12)),
                  )),
                ]),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Insights
        if (insights.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A237E).withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(children: [
              const Icon(Icons.lightbulb, color: Color(0xFF1A237E), size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(insights, style: const TextStyle(fontSize: 13, color: Color(0xFF1A237E)))),
            ]),
          ),
        const SizedBox(height: 20),

        // Daily Plan
        const Text('This Week', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
        const SizedBox(height: 12),
        ...weeklyPlan.entries.map((day) => _buildDayCard(day.key, day.value as List?)),
      ],
    );
  }

  Widget _buildDayCard(String day, List? sessions) {
    if (sessions == null || sessions.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(day[0].toUpperCase() + day.substring(1), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1A237E))),
        const SizedBox(height: 10),
        ...sessions.map((s) {
          final typeIcons = {
            'learn': Icons.menu_book,
            'practice': Icons.quiz,
            'review': Icons.replay,
            'test': Icons.assignment,
          };
          final typeColors = {
            'learn': Colors.blue,
            'practice': Colors.orange,
            'review': Colors.purple,
            'test': Colors.red,
          };
          final type = s['type'] as String? ?? 'learn';
          final icon = typeIcons[type] ?? Icons.school;
          final color = typeColors[type] ?? Colors.grey;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${s['subject']} - ${s['topic']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(s['activity'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                child: Text('${s['duration_minutes'] ?? 45} min', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
              ),
            ]),
          );
        }),
      ]),
    );
  }
}