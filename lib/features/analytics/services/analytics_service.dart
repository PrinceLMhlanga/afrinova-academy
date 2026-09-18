import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/analytics_kpis.dart';
import '../models/subject_allocation.dart';
import '../models/subject_progress.dart';
import '../models/trend_point.dart';

/// Reads analytics data for a student via four Supabase RPCs.
///
/// Design:
///   • Every method returns a nullable or empty-collection result —
///     never throws to the UI. Errors are logged and swallowed so a
///     missing RPC can't crash the dashboard.
///   • Trend calls resolve the device's IANA timezone once and cache it,
///     so the RPC buckets days in the student's local time.
///   • All four calls are cheap and independent — callers can fire
///     them in parallel via [fetchAll].
class AnalyticsService {
  AnalyticsService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Cached device timezone (IANA name, e.g. "Africa/Harare").
  String? _tzCache;

  // ─────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────

  /// Headline stats for the KPI row.
  Future<AnalyticsKpis> getKpis(String studentId) async {
    try {
      final res = await _client.rpc(
        'student_dashboard_kpis',
        params: {'p_student_id': studentId},
      );

      // RPC returns a single row (PostgREST returns a List with 1 map).
      final row = _firstRow(res);
      if (row == null) return AnalyticsKpis.empty;
      return AnalyticsKpis.fromJson(row);
    } catch (e) {
      debugPrint('[AnalyticsService] getKpis failed: $e');
      return AnalyticsKpis.empty;
    }
  }

  /// Daily trend across the last [days] days in the device's timezone.
  Future<List<TrendPoint>> getTrend(
    String studentId, {
    int days = 10,
  }) async {
    try {
      final tz = await _deviceTimezone();
      final res = await _client.rpc(
        'student_daily_trend',
        params: {
          'p_student_id': studentId,
          'p_days': days,
          'p_tz': tz,
        },
      );
      return _rows(res).map(TrendPoint.fromJson).toList(growable: false);
    } catch (e) {
      debugPrint('[AnalyticsService] getTrend failed: $e');
      return const [];
    }
  }

  /// Subject activity breakdown for the pie.
  Future<List<SubjectAllocation>> getAllocation(
    String studentId, {
    int days = 30,
  }) async {
    try {
      final res = await _client.rpc(
        'student_subject_allocation',
        params: {
          'p_student_id': studentId,
          'p_days': days,
        },
      );
      return _rows(res)
          .map(SubjectAllocation.fromJson)
          .where((s) => !s.isEmpty)
          .toList(growable: false);
    } catch (e) {
      debugPrint('[AnalyticsService] getAllocation failed: $e');
      return const [];
    }
  }

  /// Per-subject mastery / passing potential for the progress list.
  Future<List<SubjectProgress>> getSubjectProgress(String studentId) async {
    try {
      final res = await _client.rpc(
        'student_subject_progress',
        params: {'p_student_id': studentId},
      );
      return _rows(res)
          .map(SubjectProgress.fromJson)
          .toList(growable: false);
    } catch (e) {
      debugPrint('[AnalyticsService] getSubjectProgress failed: $e');
      return const [];
    }
  }

  /// Fetch everything in parallel — one round-trip from the UI's
  /// perspective. Used by the dashboard's initial load.
  Future<AnalyticsSnapshot> fetchAll(
    String studentId, {
    int trendDays = 10,
    int allocationDays = 30,
  }) async {
    final results = await Future.wait([
      getKpis(studentId),
      getTrend(studentId, days: trendDays),
      getAllocation(studentId, days: allocationDays),
      getSubjectProgress(studentId),
    ]);

    return AnalyticsSnapshot(
      kpis: results[0] as AnalyticsKpis,
      trend: results[1] as List<TrendPoint>,
      allocation: results[2] as List<SubjectAllocation>,
      subjectProgress: results[3] as List<SubjectProgress>,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Internals
  // ─────────────────────────────────────────────────────────────

  Future<String> _deviceTimezone() async {
    if (_tzCache != null) return _tzCache!;
    try {
      // flutter_timezone >= 3.x returns a TimezoneInfo object.
      //  CORRECT (New version syntax)
final info = await FlutterTimezone.getLocalTimezone();
_tzCache = info; // info is already a plain String containing your timezone (e.g. "Africa/Harare")

    } catch (e) {
      debugPrint('[AnalyticsService] timezone lookup failed: $e');
      _tzCache = 'UTC';
    }
    return _tzCache!;
  }

  /// PostgREST sometimes wraps single-row RPCs as List<Map> and
  /// sometimes as Map — normalize both shapes.
  Map<String, dynamic>? _firstRow(dynamic res) {
    if (res == null) return null;
    if (res is Map<String, dynamic>) return res;
    if (res is List && res.isNotEmpty && res.first is Map) {
      return Map<String, dynamic>.from(res.first as Map);
    }
    return null;
  }

  List<Map<String, dynamic>> _rows(dynamic res) {
    if (res == null) return const [];
    if (res is List) {
      return res
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList(growable: false);
    }
    return const [];
  }
}

/// Bundles all four analytics results into one object so the dashboard
/// can hold a single piece of state instead of four.
class AnalyticsSnapshot {
  final AnalyticsKpis kpis;
  final List<TrendPoint> trend;
  final List<SubjectAllocation> allocation;
  final List<SubjectProgress> subjectProgress;

  const AnalyticsSnapshot({
    required this.kpis,
    required this.trend,
    required this.allocation,
    required this.subjectProgress,
  });

  static const AnalyticsSnapshot empty = AnalyticsSnapshot(
    kpis: AnalyticsKpis.empty,
    trend: [],
    allocation: [],
    subjectProgress: [],
  );

  bool get isEmpty =>
      kpis.isEmpty &&
      trend.every((t) => t.isEmpty) &&
      allocation.isEmpty &&
      subjectProgress.every((s) => s.isEmpty);
}