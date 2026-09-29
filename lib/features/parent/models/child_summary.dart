/// A parent's view of a linked student.
///
/// Combines data from `parent_student_links`, `profiles`, and `levels`
/// into a single object the UI can render without further lookups.
class ChildSummary {
  /// The `parent_student_links.id`. This is what we use for
  /// approve/decline actions — NOT the student's profile id.
  final String linkId;

  /// The child's `profiles.id`. Used to fetch their analytics.
  final String studentId;

  final String fullName;
  final String? displayName;
  final String? avatarUrl;
  final String? levelName;

  /// 'mother' | 'father' | 'guardian' | 'other'
  final String relationship;

  /// 'pending' | 'active' | 'denied' | 'revoked'
  final String status;

  final DateTime linkedAt;

  final bool isSubscribed;
  final DateTime? subscriptionExpiresAt;

  const ChildSummary({
    required this.linkId,
    required this.studentId,
    required this.fullName,
    this.displayName,
    this.avatarUrl,
    this.levelName,
    required this.relationship,
    required this.status,
    required this.linkedAt,
    this.isSubscribed = false,
    this.subscriptionExpiresAt,
  });

  bool get hasActivePremium {
    if (!isSubscribed) return false;
    final exp = subscriptionExpiresAt;
    if (exp == null) return true;   // subscribed with no expiry = lifetime
    return exp.isAfter(DateTime.now().toUtc());
  }

  /// Best display name — falls back to full name, then 'Student'.
  String get preferredName {
    final d = displayName?.trim();
    if (d != null && d.isNotEmpty) return d;
    final f = fullName.trim();
    if (f.isNotEmpty) return f;
    return 'Student';
  }

  /// Initials for the avatar.
  String get initials {
    final name = preferredName.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  bool get isActive => status == 'active';
  bool get isPending => status == 'pending';
  bool get isDenied => status == 'denied';

  factory ChildSummary.fromLinkJson(Map<String, dynamic> json) {
    final student = json['student'] as Map<String, dynamic>? ?? {};
    final levels = student['levels'] as Map<String, dynamic>?;

    return ChildSummary(
      linkId: json['id'] as String,
      studentId: student['id'] as String? ?? json['student_id'] as String,
      fullName: student['full_name'] as String? ?? 'Student',
      displayName: student['display_name'] as String?,
      avatarUrl: student['avatar_url'] as String?,
      levelName: levels?['name'] as String?,
      relationship: json['relationship'] as String? ?? 'parent',
      status: json['status'] as String? ?? 'pending',
      linkedAt: DateTime.tryParse(json['linked_at'] as String? ?? '') ??
          DateTime.now(),
      isSubscribed: student['is_subscribed'] == true,
      subscriptionExpiresAt: student['subscription_expires_at'] != null
          ? DateTime.tryParse(student['subscription_expires_at'] as String)
              ?.toUtc()
          : null,
    );
  }
}
