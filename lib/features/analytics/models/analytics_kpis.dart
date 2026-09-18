/// Snapshot of a student's headline stats.
///
/// Backed by the `student_dashboard_kpis` RPC — one row, one snapshot.
/// Nullable fields mean "no data yet" (e.g. student has never taken an
/// MCQ exam). The UI should render `--` for nulls, not `0`.
class AnalyticsKpis {
  final double? aiExamAvg;
  final int flashcardsMastered;
  final int flashcardsTotal;
  final int objectivesMastered;
  final int objectivesTotal;
  final double? examPaperAvg;
  final int lessonsCompleted;
  final double? mcqAvg;
  final int papersAttempted;

  const AnalyticsKpis({
    required this.aiExamAvg,
    required this.flashcardsMastered,
    required this.flashcardsTotal,
    required this.objectivesMastered,
    required this.objectivesTotal,
    required this.examPaperAvg,
    required this.lessonsCompleted,
    required this.mcqAvg,
    required this.papersAttempted,
  });

  factory AnalyticsKpis.fromJson(Map<String, dynamic> json) {
    return AnalyticsKpis(
      aiExamAvg: _toDouble(json['ai_exam_avg']),
      flashcardsMastered: _toInt(json['flashcards_mastered']),
      flashcardsTotal: _toInt(json['flashcards_total']),
      objectivesMastered: _toInt(json['objectives_mastered']),
      objectivesTotal: _toInt(json['objectives_total']),
      examPaperAvg: _toDouble(json['exam_paper_avg']),
      lessonsCompleted: _toInt(json['lessons_completed']),
      mcqAvg: _toDouble(json['mcq_avg']),
      papersAttempted: _toInt(json['papers_attempted']),
    );
  }

  /// Convenience: objective mastery as a 0–1 ratio.
  double get objectiveMasteryRatio =>
      objectivesTotal == 0 ? 0 : objectivesMastered / objectivesTotal;

  /// Convenience: flashcard mastery as a 0–1 ratio.
  double get flashcardMasteryRatio =>
      flashcardsTotal == 0 ? 0 : flashcardsMastered / flashcardsTotal;

  /// True when this student has zero data across every source.
  /// The dashboard uses this to render a "get started" empty state.
  bool get isEmpty =>
      aiExamAvg == null &&
      examPaperAvg == null &&
      mcqAvg == null &&
      flashcardsTotal == 0 &&
      objectivesMastered == 0 &&
      lessonsCompleted == 0;

  /// Empty snapshot — useful as an initial state before the RPC resolves.
  static const AnalyticsKpis empty = AnalyticsKpis(
    aiExamAvg: null,
    flashcardsMastered: 0,
    flashcardsTotal: 0,
    objectivesMastered: 0,
    objectivesTotal: 0,
    examPaperAvg: null,
    lessonsCompleted: 0,
    mcqAvg: null,
    papersAttempted: 0,
  );
}

// ─────────────────────────────────────────────────────────────
// Shared JSON coercion helpers.
// Postgres `numeric` can arrive as int, double, or string depending
// on driver version — so we normalize defensively.
// ─────────────────────────────────────────────────────────────

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}