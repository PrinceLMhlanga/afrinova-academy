import 'package:flutter/material.dart';

import '../../core/notification_service.dart';
import '../../core/shell/shell_app_bar.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';

/// Full-screen notifications center.
///
/// - Lists the current user's notifications, newest first.
/// - Groups by day (Today / Yesterday / Older).
/// - Special card for `parent_link_request` with Approve/Deny buttons.
/// - Everything else renders as a generic card.
/// - Tapping a generic card marks it read.
/// - Realtime: new notifications appear as they're inserted.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _service = NotificationService.instance;

  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  /// Per-link busy flag while the student is approving/denying.
  final Set<String> _respondingLinks = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final items = await _service.fetchMyNotifications();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _respond({
    required String notificationId,
    required String linkId,
    required bool approve,
  }) async {
    setState(() => _respondingLinks.add(linkId));
    final err = await _service.respondToParentLink(
      notificationId: notificationId,
      linkId: linkId,
      approve: approve,
    );
    if (!mounted) return;
    setState(() => _respondingLinks.remove(linkId));

    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    // Local update — remove the action buttons by flipping status in
    // the cached row.
    setState(() {
      _items = _items.map((n) {
        if (n['id'] == notificationId) {
          return {
            ...n,
            'is_read': true,
            'data': {
              ...(n['data'] as Map? ?? {}),
              'resolved': approve ? 'approved' : 'denied',
            },
          };
        }
        return n;
      }).toList();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(approve
            ? 'Link approved.'
            : 'Link request declined.'),
        backgroundColor: approve ? AppColors.success : null,
      ),
    );
  }

  Future<void> _markAllRead() async {
    await _service.markAllRead();
    if (!mounted) return;
    setState(() {
      _items = _items
          .map((n) => {...n, 'is_read': true})
          .toList(growable: false);
    });
  }

  Future<void> _handleTap(Map<String, dynamic> item) async {
  final id = item['id'] as String;

  // Optimistically flip to read in local state
  if (item['is_read'] == false) {
    setState(() {
      _items = _items.map((n) {
        if (n['id'] == id) {
          return {...n, 'is_read': true};
        }
        return n;
      }).toList(growable: false);
    });

    // Persist
    await _service.markRead(id);
  }

  // TODO: navigate if data carries a route (later)
}

Future<void> _confirmRevoke(Map<String, dynamic> item) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Revoke access?'),
      content: const Text(
        'This parent will no longer see your progress, exam scores, '
        'or activity. They would need to send a new link request to '
        'regain access.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.danger,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Revoke'),
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  final data = item['data'] as Map? ?? {};
  final linkId = data['link_id'] as String?;
  final notificationId = item['id'] as String;
  if (linkId == null) return;

  setState(() => _respondingLinks.add(linkId));

  final err = await _service.revokeParentLink(
    notificationId: notificationId,
    linkId: linkId,
  );

  if (!mounted) return;
  setState(() => _respondingLinks.remove(linkId));

  if (err != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err),
        backgroundColor: AppColors.danger,
      ),
    );
    return;
  }

  // Update local state.
  setState(() {
    _items = _items.map((n) {
      if (n['id'] == notificationId) {
        return {
          ...n,
          'data': {
            ...(n['data'] as Map? ?? {}),
            'resolved': 'revoked',
          },
        };
      }
      return n;
    }).toList(growable: false);
  });

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Access revoked.'),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundTop,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(AppSpacing.topbarHeight),
        child: ShellAppBar(
          title: 'Notifications',
          onBack: () => Navigator.of(context).maybePop(),
          actions: [
            if (_items.any((n) => n['is_read'] == false))
              TextButton(
                onPressed: _markAllRead,
                child: Text(
                  'Mark all read',
                  style: AppTextStyles.labelMd.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            const SizedBox(width: 8),
          ],
        ),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 40, color: AppColors.textTertiary),
            const SizedBox(height: AppSpacing.md),
            Text(_error!, style: AppTextStyles.bodySm),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _service.watchMyNotifications(),
      builder: (context, snapshot) {
        final items =
            snapshot.hasData && snapshot.data!.isNotEmpty
                ? snapshot.data!
                : _items;

        if (items.isEmpty) {
          return _EmptyState();
        }

        final grouped = _groupByDay(items);

        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              for (final entry in grouped.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.md,
                    bottom: AppSpacing.sm,
                  ),
                  child: Text(
                    entry.key.toUpperCase(),
                    style: AppTextStyles.overline,
                  ),
                ),
                for (final item in entry.value)
                  _NotificationCard(
                    item: item,
                    busy: _respondingLinks.contains(
                      (item['data'] as Map?)?['link_id'],
                    ),
                    onRespond: (approve) {
                      final data = item['data'] as Map? ?? {};
                      final linkId = data['link_id'] as String?;
                      if (linkId == null) return;
                      _respond(
                        notificationId: item['id'] as String,
                        linkId: linkId,
                        approve: approve,
                      );
                    },
                    onRevoke: () => _confirmRevoke(item),
                    onTap: () => _handleTap(item),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Group by Today / Yesterday / Older, preserving order.
  Map<String, List<Map<String, dynamic>>> _groupByDay(
    List<Map<String, dynamic>> items,
  ) {
    final today = <Map<String, dynamic>>[];
    final yesterday = <Map<String, dynamic>>[];
    final older = <Map<String, dynamic>>[];

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfYesterday = startOfToday.subtract(const Duration(days: 1));

    for (final n in items) {
      final createdStr = n['created_at'] as String?;
      final created =
          createdStr != null ? DateTime.tryParse(createdStr)?.toLocal() : null;
      if (created == null) {
        older.add(n);
      } else if (!created.isBefore(startOfToday)) {
        today.add(n);
      } else if (!created.isBefore(startOfYesterday)) {
        yesterday.add(n);
      } else {
        older.add(n);
      }
    }

    return {
      if (today.isNotEmpty) 'Today': today,
      if (yesterday.isNotEmpty) 'Yesterday': yesterday,
      if (older.isNotEmpty) 'Earlier': older,
    };
  }
}

// ─────────────────────────────────────────────────────────────
// Generic notification card
// ─────────────────────────────────────────────────────────────

class _NotificationCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool busy;
  final void Function(bool approve) onRespond;
  final VoidCallback onRevoke;
  final VoidCallback onTap;

  const _NotificationCard({
    required this.item,
    required this.busy,
    required this.onRespond,
    required this.onRevoke,
    required this.onTap,
  });

  bool get _isParentLink =>
      item['type'] == 'parent_link_request';

  bool get _isResolved {
    final data = item['data'] as Map? ?? {};
    return data['resolved'] != null;
  }

  String get _resolvedLabel {
    final data = item['data'] as Map? ?? {};
    switch (data['resolved']) {
      case 'approved':
        return 'Approved';
      case 'denied':
        return 'Declined';
      default:
        return '';
    }
  }

  IconData get _icon {
    switch (item['type']) {
      case 'live_lesson':
        return Icons.live_tv_rounded;
      case 'enrollment':
      case 'enrollment_request':
        return Icons.school_rounded;
      case 'payment':
        return Icons.payments_rounded;
      case 'new_exam':
      case 'new_exam_paper':
        return Icons.quiz_rounded;
      case 'new_lesson':
        return Icons.menu_book_rounded;
      case 'new_resource':
        return Icons.library_books_rounded;
      case 'referral_reward':
      case 'referral_reward_earned':
      case 'referral_trial':
        return Icons.card_giftcard_rounded;
      case 'parent_link_request':
        return Icons.family_restroom_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _accent(BuildContext context) {
    switch (item['type']) {
      case 'parent_link_request':
        return AppColors.primary;
      case 'referral_reward':
      case 'referral_reward_earned':
      case 'referral_trial':
        return const Color(0xFF8B5CF6);
      case 'payment':
        return AppColors.chartPaper;
      case 'live_lesson':
        return AppColors.danger;
      default:
        return AppColors.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRead = item['is_read'] == true;
    final accent = _accent(context);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: isRead ? AppColors.surfaceSubtle : AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: Border.all(
          color: isRead
              ? AppColors.border
              : accent.withOpacity(0.25),
        ),
        boxShadow: isRead ? null : AppColors.shadowCard,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        child: InkWell(
          onTap: _isParentLink ? null : onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusButton,
                        ),
                      ),
                      child: Icon(_icon, size: 20, color: accent),
                    ),
                    const SizedBox(width: AppSpacing.md),

                    // Title + body
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['title'] as String? ?? '',
                            style: AppTextStyles.labelMd.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: isRead
                                  ? FontWeight.w600
                                  : FontWeight.w700,
                            ),
                          ),
                          if ((item['body'] as String?)?.isNotEmpty == true) ...[
                            const SizedBox(height: 2),
                            Text(
                              item['body'] as String,
                              style: AppTextStyles.caption,
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Unread dot
                    if (!isRead)
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(
                          top: 6,
                          left: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),

                // Parent-link actions
              if (_isParentLink) ...[
  const SizedBox(height: AppSpacing.md),
  const Divider(height: 1),
  const SizedBox(height: AppSpacing.md),
  _buildParentLinkActions(),
],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildParentLinkActions() {
  final data = item['data'] as Map? ?? {};
  final resolved = data['resolved'] as String?;

  // No resolution yet — show both buttons.
  if (resolved == null) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: busy ? null : () => onRespond(false),
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Decline'),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: FilledButton(
            onPressed: busy ? null : () => onRespond(true),
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Approve'),
          ),
        ),
      ],
    );
  }

  // Approved — show a Linked chip and a Revoke action.
  if (resolved == 'approved') {
    return Row(
      children: [
        const _ResolvedBadge(label: 'Linked'),
        const Spacer(),
        TextButton.icon(
          onPressed: busy ? null : onRevoke,
          icon: const Icon(Icons.link_off_rounded, size: 16),
          label: const Text('Revoke'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.danger,
          ),
        ),
      ],
    );
  }

  // Denied or revoked — just a status chip. Nothing to do.
  if (resolved == 'denied') {
    return const Align(
      alignment: Alignment.centerLeft,
      child: _ResolvedBadge(label: 'Declined'),
    );
  }

  // Fallback for any other resolved state.
  return Align(
    alignment: Alignment.centerLeft,
    child: _ResolvedBadge(label: resolved),
  );
}
}

class _ResolvedBadge extends StatelessWidget {
  final String label;
  const _ResolvedBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final approved = label == 'Approved';
    final color = approved ? AppColors.success : AppColors.textTertiary;
    return Row(
      children: [
        Icon(
          approved
              ? Icons.check_circle_rounded
              : Icons.cancel_rounded,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.notifications_none_rounded,
                size: 32,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('You\'re all caught up',
                style: AppTextStyles.headingMd),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Notifications about lessons, exams, and payments will '
              'appear here.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySm,
            ),
          ],
        ),
      ),
    );
  }
}