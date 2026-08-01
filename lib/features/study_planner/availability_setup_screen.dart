import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';

class AvailabilitySetupScreen extends StatefulWidget {
  const AvailabilitySetupScreen({super.key});

  @override
  State<AvailabilitySetupScreen> createState() => _AvailabilitySetupScreenState();
}

class _AvailabilitySetupScreenState extends State<AvailabilitySetupScreen> {
  final AuthService _authService = AuthService();
  bool _isSaving = false;
  
  final Map<String, List<TimeRange>> _availability = {
    'monday': [],
    'tuesday': [],
    'wednesday': [],
    'thursday': [],
    'friday': [],
    'saturday': [],
    'sunday': [],
  };

  @override
  void initState() {
    super.initState();
    _loadExistingAvailability();
  }

  Future<void> _loadExistingAvailability() async {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    try {
      final data = await Supabase.instance.client
          .from('student_availability')
          .select('*')
          .eq('student_id', userId)
          .maybeSingle();

      if (data != null) {
        setState(() {
          for (final day in _availability.keys) {
            final hoursStr = data['${day}_hours'] as String?;
            if (hoursStr != null && hoursStr.isNotEmpty) {
              _availability[day] = _parseTimeRanges(hoursStr);
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Load availability error: $e');
    }
  }

  List<TimeRange> _parseTimeRanges(String hoursStr) {
    return hoursStr.split(',').map((range) {
      final parts = range.trim().split('-');
      return TimeRange(
        start: _parseTime(parts[0]),
        end: _parseTime(parts[1]),
      );
    }).toList();
  }

  TimeOfDay _parseTime(String time) {
    final parts = time.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  Future<void> _addTimeSlot(String day) async {
    TimeOfDay? start = const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay? end = const TimeOfDay(hour: 10, minute: 0);

    // Pick start time
    final pickedStart = await showTimePicker(context: context, initialTime: start);
    if (pickedStart == null) return;

    final pickedEnd = await showTimePicker(context: context, initialTime: end);
    if (pickedEnd == null) return;

    setState(() {
      _availability[day]!.add(TimeRange(start: pickedStart, end: pickedEnd));
      _availability[day]!.sort((a, b) => a.start.hour.compareTo(b.start.hour));
    });
  }

  void _removeTimeSlot(String day, int index) {
    setState(() {
      _availability[day]!.removeAt(index);
    });
  }

  Future<void> _saveAvailability() async {
  final userId = _authService.currentUserId;
  if (userId == null) return;

  setState(() => _isSaving = true);

  try {
    final data = <String, dynamic>{'student_id': userId};
    
    for (final day in _availability.keys) {
      final ranges = _availability[day]!
          .map((r) => '${r.start.hour.toString().padLeft(2, '0')}:${r.start.minute.toString().padLeft(2, '0')}-${r.end.hour.toString().padLeft(2, '0')}:${r.end.minute.toString().padLeft(2, '0')}')
          .join(',');
      data['${day}_hours'] = ranges.isEmpty ? null : ranges;
    }

    await Supabase.instance.client
        .from('student_availability')
        .upsert(data, onConflict: 'student_id');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Availability saved! ✅'), backgroundColor: Color(0xFF4CAF50)),
      );
      Navigator.pop(context, true);
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Study Availability'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveAvailability,
            child: _isSaving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A237E).withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, color: Color(0xFF1A237E), size: 20),
              SizedBox(width: 10),
              Expanded(child: Text('Set when you are available to study each day. This helps create a realistic study plan.', style: TextStyle(fontSize: 13, color: Color(0xFF1A237E)))),
            ]),
          ),
          const SizedBox(height: 16),
          ..._availability.entries.map((entry) => _buildDayCard(entry.key, entry.value)),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildDayCard(String day, List<TimeRange> slots) {
    final dayName = day[0].toUpperCase() + day.substring(1);
    final isWeekend = day == 'saturday' || day == 'sunday';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isWeekend ? Border.all(color: Colors.orange.withOpacity(0.3)) : null,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(dayName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isWeekend ? Colors.orange : const Color(0xFF1A237E))),
          if (isWeekend) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
              child: const Text('Weekend', style: TextStyle(fontSize: 10, color: Colors.orange)),
            ),
          ],
          const Spacer(),
          TextButton.icon(
            onPressed: () => _addTimeSlot(day),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add', style: TextStyle(fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 8),
        if (slots.isEmpty)
          Text('No time set', style: TextStyle(fontSize: 12, color: Colors.grey.shade400))
        else
          ...slots.asMap().entries.map((e) {
            final index = e.key;
            final slot = e.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A237E).withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.access_time, size: 16, color: Color(0xFF1A237E)),
                const SizedBox(width: 8),
                Text('${slot.start.format(context)} - ${slot.end.format(context)}', style: const TextStyle(fontSize: 13)),
                const Spacer(),
                GestureDetector(
                  onTap: () => _removeTimeSlot(day, index),
                  child: const Icon(Icons.close, size: 16, color: Colors.red),
                ),
              ]),
            );
          }),
      ]),
    );
  }
}

class TimeRange {
  final TimeOfDay start;
  final TimeOfDay end;

  TimeRange({required this.start, required this.end});
}