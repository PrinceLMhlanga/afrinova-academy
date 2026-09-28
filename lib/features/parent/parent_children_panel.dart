import 'package:flutter/material.dart';

import '../../core/shell/panel_scaffold.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import 'models/child_summary.dart';
import 'services/parent_service.dart';
import 'widgets/link_student_dialog.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The Children tab.
///
/// Lists all links (pending, active, denied, revoked) with status
/// indicators. Lets the parent send new link requests and unlink
/// existing ones.
class ParentChildrenPanel extends StatefulWidget {
  const ParentChildrenPanel({super.key});

  @override
  State<ParentChildrenPanel> createState() => _ParentChildrenPanelState();
}

class _ParentChildrenPanelState extends State<ParentChildrenPanel>
    with AutomaticKeepAliveClientMixin {
  final _service = ParentService();

  List<ChildSummary> _children = const [];
  bool _loading = true;
  String? _error;

  final Set<String> _unlinking = {};

  @override
  bool get wantKeepAlive => true;

 StreamSubscription<List<Map<String, dynamic>>>? _linksSub;
Timer? _reloadDebounce;

@override
void initState() {
  super.initState();
  _bootstrap();
}

Future<void> _bootstrap() async {
  for (var i = 0; i < 30; i++) {
    final session = Supabase.instance.client.auth.currentSession;
    if (session?.accessToken != null) break;
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
  }
  if (!mounted) return;
  await _load();
  _subscribeToLinks();
}

@override
void dispose() {
  _linksSub?.cancel();
  _reloadDebounce?.cancel();
  super.dispose();
}

void _subscribeToLinks() {
  final parentId = Supabase.instance.client.auth.currentUser?.id;
  if (parentId == null) return;

  var firstEventSeen = false;

  _linksSub = Supabase.instance.client
      .from('parent_student_links')
      .stream(primaryKey: ['id'])
      .eq('parent_id', parentId)
      .listen(
    (rows) {
      if (!firstEventSeen) {
        firstEventSeen = true;
        return;
      }
      _reloadDebounce?.cancel();
      _reloadDebounce = Timer(const Duration(milliseconds: 500), () {
        if (mounted) _load();
      });
    },
    onError: (e) =>
        debugPrint('[ParentChildrenPanel] links stream error: $e'),
  );
}

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final children = await _service.getAllLinksTyped();
      if (!mounted) return;
      setState(() {
        _children = children;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _openLinkDialog() async {
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) => const LinkStudentDialog(),
    );
    if (sent == true) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Link request sent.'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _confirmUnlink(ChildSummary child) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          child.isActive ? 'Unlink student?' : 'Cancel request?',
        ),
        content: Text(
          child.isActive
              ? 'You will no longer see ${child.preferredName}\'s progress.'
              : 'The pending request to ${child.preferredName} will be cancelled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _unlinking.add(child.linkId));
    await _service.unlink(child.linkId);
    if (!mounted) return;
    setState(() {
      _unlinking.remove(child.linkId);
      _children = _children
          .where((c) => c.linkId != child.linkId)
          .toList(growable: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return PanelScaffold(
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          const SizedBox(height: AppSpacing.xxl),
          const Icon(Icons.cloud_off_rounded,
              size: 48, color: AppColors.textTertiary),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Couldn\'t load your children',
            textAlign: TextAlign.center,
            style: AppTextStyles.headingMd,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: OutlinedButton(
              onPressed: _load,
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        // Header
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your Children',
                      style: AppTextStyles.headingLg),
                  const SizedBox(height: 4),
                  Text(
                    _children.isEmpty
                        ? 'Link a student to get started.'
                        : '${_children.where((c) => c.isActive).length} '
                          'linked · ${_children.length} total',
                    style: AppTextStyles.bodySm,
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _openLinkDialog,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Link'),
            ),
          ],
        ),

        const SizedBox(height: AppSpacing.xl),

        if (_children.isEmpty)
          const _EmptyChildrenState()
        else
          for (final child in _children)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _ChildRow(
                child: child,
                unlinking: _unlinking.contains(child.linkId),
                onUnlink: () => _confirmUnlink(child),
              ),
            ),

        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Child row
// ─────────────────────────────────────────────────────────────

class _ChildRow extends StatelessWidget {
  final ChildSummary child;
  final bool unlinking;
  final VoidCallback onUnlink;

  const _ChildRow({
    required this.child,
    required this.unlinking,
    required this.onUnlink,
  });

  ({Color bg, Color border, Color fg, IconData icon, String label})
      get _statusVisuals {
    if (child.isActive) {
      return (
        bg: AppColors.successBg,
        border: AppColors.successBorder,
        fg: AppColors.success,
        icon: Icons.check_circle_rounded,
        label: 'Linked',
      );
    }
    if (child.isPending) {
      return (
        bg: AppColors.warningBg,
        border: AppColors.warningBorder,
        fg: AppColors.warning,
        icon: Icons.schedule_rounded,
        label: 'Pending',
      );
    }
    if (child.isDenied) {
      return (
        bg: AppColors.dangerBg,
        border: AppColors.dangerBorder,
        fg: AppColors.danger,
        icon: Icons.cancel_rounded,
        label: 'Declined',
      );
    }
    return (
      bg: AppColors.surfaceSubtle,
      border: AppColors.border,
      fg: AppColors.textSecondary,
      icon: Icons.remove_circle_outline,
      label: child.status,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _statusVisuals;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              gradient: AppColors.brandGradient,
              shape: BoxShape.circle,
            ),
            child: Text(
              child.initials,
              style: AppTextStyles.labelMd.copyWith(color: Colors.white),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(child.preferredName, style: AppTextStyles.labelMd),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      child.relationship,
                      style: AppTextStyles.captionXs,
                    ),
                    if (child.levelName != null) ...[
                      Text(' · ', style: AppTextStyles.captionXs),
                      Text(
                        child.levelName!,
                        style: AppTextStyles.captionXs,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: s.bg,
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              border: Border.all(color: s.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(s.icon, size: 14, color: s.fg),
                const SizedBox(width: 4),
                Text(
                  s.label,
                  style: AppTextStyles.captionXs.copyWith(
                    color: s.fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            onPressed: unlinking ? null : onUnlink,
            icon: unlinking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(
                    Icons.delete_outline,
                    color: AppColors.textTertiary,
                    size: 20,
                  ),
            tooltip: child.isActive ? 'Unlink' : 'Cancel request',
          ),
        ],
      ),
    );
  }
}

class _EmptyChildrenState extends StatelessWidget {
  const _EmptyChildrenState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
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
                Icons.person_add_alt_1_rounded,
                size: 32,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('No children linked',
                style: AppTextStyles.headingMd),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Tap "Link" above to send a request to your child\'s '
              'account.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySm,
            ),
          ],
        ),
      ),
    );
  }
}