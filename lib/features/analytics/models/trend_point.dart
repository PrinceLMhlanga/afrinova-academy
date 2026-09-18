/// A single day in the student's performance trend.
///
/// Backed by `student_daily_trend`. Each numeric field is nullable —
/// null means "no activity of this kind on this day", which the chart
/// renders as a gap rather than a dip to zero.
class TrendPoint {
  final DateTime day;
  final double? aiAvg;
  final double? mcqAvg;
  final double? paperAvg;
  final double? blendedAvg;

  const TrendPoint({
    required this.day,
    this.aiAvg,
    this.mcqAvg,
    this.paperAvg,
    this.blendedAvg,
  });

  factory TrendPoint.fromJson(Map<String, dynamic> json) {
    return TrendPoint(
      day: _parseDate(json['day']) ?? DateTime.now(),
      aiAvg: _toDouble(json['ai_avg']),
      mcqAvg: _toDouble(json['mcq_avg']),
      paperAvg: _toDouble(json['paper_avg']),
      blendedAvg: _toDouble(json['blended_avg']),
    );
  }

  /// True when the student did nothing of any kind on this day.
  bool get isEmpty =>
      aiAvg == null && mcqAvg == null && paperAvg == null;
}

/// Postgres returns `date` as `YYYY-MM-DD` string via the supabase
/// client. Parse it as a local date, not UTC, to avoid off-by-one.
DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) {
    // Try ISO first, then date-only.
    final iso = DateTime.tryParse(v);
    if (iso != null) return iso;
    final parts = v.split('-');
    if (parts.length == 3) {
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (y != null && m != null && d != null) {
        return DateTime(y, m, d);
      }
    }
  }
  return null;
}

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}