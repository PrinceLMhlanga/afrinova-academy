/// One subject's mastery / passing-potential row.
///
/// Backed by `student_subject_progress`. `passingPotential` is the
/// headline number the progress bar renders; the sub-metrics are
/// available for the detail sheet.
class SubjectProgress {
  final String subjectId;
  final String subjectName;
  final String colorHex;
  final int objectivesMastered;
  final int objectivesTotal;
  final double practicePassRate;
  final double flashcardMastery;
  final double passingPotential;

  const SubjectProgress({
    required this.subjectId,
    required this.subjectName,
    required this.colorHex,
    required this.objectivesMastered,
    required this.objectivesTotal,
    required this.practicePassRate,
    required this.flashcardMastery,
    required this.passingPotential,
  });

  factory SubjectProgress.fromJson(Map<String, dynamic> json) {
    return SubjectProgress(
      subjectId: json['subject_id'] as String? ?? '',
      subjectName: json['subject_name'] as String? ?? 'Unknown',
      colorHex: json['color_hex'] as String? ?? '#1A237E',
      objectivesMastered: _toInt(json['objectives_mastered']),
      objectivesTotal: _toInt(json['objectives_total']),
      practicePassRate: _toDouble(json['practice_pass_rate']) ?? 0,
      flashcardMastery: _toDouble(json['flashcard_mastery']) ?? 0,
      passingPotential: _toDouble(json['passing_potential']) ?? 0,
    );
  }

  /// 0–1 ratio of objectives mastered.
  double get objectiveRatio =>
      objectivesTotal == 0 ? 0 : objectivesMastered / objectivesTotal;

  /// True when there's nothing meaningful to show.
  bool get isEmpty =>
      objectivesTotal == 0 && practicePassRate == 0 && flashcardMastery == 0;
}

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}