/// One subject's slice of the student's activity pie.
///
/// Backed by `student_subject_allocation`. The `total` is what drives
/// slice size; the individual counts feed the tooltip / detail sheet.
class SubjectAllocation {
  final String subjectId;
  final String subjectName;
  final String colorHex;
  final int flashcards;
  final int summaries;
  final int practiceExams;
  final int examAttempts;
  final int lessonsWatched;
  final int total;

  const SubjectAllocation({
    required this.subjectId,
    required this.subjectName,
    required this.colorHex,
    required this.flashcards,
    required this.summaries,
    required this.practiceExams,
    required this.examAttempts,
    required this.lessonsWatched,
    required this.total,
  });

  factory SubjectAllocation.fromJson(Map<String, dynamic> json) {
    return SubjectAllocation(
      subjectId: json['subject_id'] as String? ?? '',
      subjectName: json['subject_name'] as String? ?? 'Unknown',
      colorHex: json['color_hex'] as String? ?? '#1A237E',
      flashcards: _toInt(json['flashcards']),
      summaries: _toInt(json['summaries']),
      practiceExams: _toInt(json['practice_exams']),
      examAttempts: _toInt(json['exam_attempts']),
      lessonsWatched: _toInt(json['lessons_watched']),
      total: _toInt(json['total']),
    );
  }

  /// True when this subject has zero activity in the window.
  /// The pie should filter these out before rendering.
  bool get isEmpty => total == 0;

  /// Human-readable breakdown for tooltips / detail views.
  List<MapEntry<String, int>> get breakdown => [
        MapEntry('Flashcards', flashcards),
        MapEntry('Summaries', summaries),
        MapEntry('Practice exams', practiceExams),
        MapEntry('MCQ exams', examAttempts),
        MapEntry('Lessons', lessonsWatched),
      ].where((e) => e.value > 0).toList();
}

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}