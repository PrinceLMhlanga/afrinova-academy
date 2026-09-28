import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_drawer.dart';
import 'app_sidebar.dart';
import 'app_topbar.dart';
import 'nav_registry.dart';
import '../notification_service.dart';
import '../../features/notifications/notifications_screen.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';


/// The responsive app shell for student-facing navigation.
///
/// Layout modes:
///   • Mobile  (< 900px) — drawer nav; burger in the topbar opens it.
///   • Tablet  (900–1200px) — collapsed sidebar (72px) always visible.
///   • Desktop (>= 1200px) — full sidebar (240px), user-collapsible.
///
/// Panel switching:
///   • [NavBehavior.panel] items swap the viewport via [IndexedStack],
///     preserving each panel's state across switches.
///   • [NavBehavior.push] items call [onPushRoute], which the host
///     screen (HomeScreen) implements to route to full-screen pages.
class AppShell extends StatefulWidget {
  final String userName;
  final String userRole;
  final void Function(BuildContext context, String key) onPushRoute;
  final VoidCallback? onNotificationsTap;
  final int notificationCount;
  final VoidCallback? onAccountTap;   // NEW

  const AppShell({
    super.key,
    required this.userName,
    required this.userRole,
    required this.onPushRoute,
    this.onNotificationsTap,
    this.notificationCount = 0,
    this.onAccountTap,               // NEW
  });

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> with WidgetsBindingObserver {
  String _activePanelKey = 'dashboard';
  bool _sidebarCollapsed = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _unreadNotifications = 0;
  StreamSubscription<List<Map<String, dynamic>>>? _notificationSub;

 @override
void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this);   // AppShell only
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

  try {
    await Supabase.instance.client.auth.refreshSession();
  } catch (e) {
    debugPrint('[AppShell] refreshSession failed (non-fatal): $e');
  }

  if (!mounted) return;

  _refreshUnreadCount();
  _subscribeToNotifications();
}

@override
void dispose() {
  _notificationSub?.cancel();
  WidgetsBinding.instance.removeObserver(this);
  super.dispose();
}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshUnreadCount();
    }
  }

  void _subscribeToNotifications() {
    if (_notificationSub != null) return;
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return;

  _notificationSub = Supabase.instance.client
      .from('notifications')
      .stream(primaryKey: ['id'])
      .eq('user_id', userId)
      .listen(
    (rows) {
      final unread = rows.where((r) => r['is_read'] == false).length;
      if (mounted && unread != _unreadNotifications) {
        setState(() => _unreadNotifications = unread);
      }
    },
    onError: (e) {
      debugPrint('[AppShell] notification stream error: $e');
    },
  );
}

  Future<void> _refreshUnreadCount() async {
    final count = await NotificationService.instance.getUnreadCount();
    if (mounted) setState(() => _unreadNotifications = count);
  }
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < AppSpacing.breakpointMobile;
    final isTablet = width >= AppSpacing.breakpointMobile &&
        width < AppSpacing.breakpointDesktop;

    final effectiveCollapsed = isTablet ? true : _sidebarCollapsed;

    final items = widget.userRole == 'parent'
    ? NavRegistry.allForParent(onPush: widget.onPushRoute)
    : NavRegistry.all(onPush: widget.onPushRoute);
    final panelItems =
        items.where((i) => i.behavior == NavBehavior.panel).toList();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.backgroundTop,
      drawer: isMobile
          ? AppDrawer(
              items: items,
              activeKey: _activePanelKey,
              onSelect: (item) => _handleSelect(item, isMobile: true),
              userName: widget.userName,
              userRole: widget.userRole,
              onAccountTap: widget.onAccountTap,
            )
          : null,
      body: Column(
        children: [
          AppTopbar(
            title: _titleForActivePanel(items),
            isMobile: isMobile,
            sidebarCollapsed: effectiveCollapsed,
            onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
            onToggleSidebar: () =>
                setState(() => _sidebarCollapsed = !_sidebarCollapsed),
            onNotificationsTap: () async {
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const NotificationsScreen()),
  );
  // Refresh count when the user comes back from the screen.
  _refreshUnreadCount();
},
            notificationCount: _unreadNotifications,
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!isMobile)
                  AppSidebar(
                    items: items,
                    activeKey: _activePanelKey,
                    collapsed: effectiveCollapsed,
                    onToggleCollapse: () =>
                        setState(() => _sidebarCollapsed = !_sidebarCollapsed),
                    onSelect: (item) =>
                        _handleSelect(item, isMobile: false),
                    userName: widget.userName,
                    userRole: widget.userRole,
                    onAccountTap: widget.onAccountTap,
                  ),
                Expanded(
                  child: _PanelViewport(
                    panels: panelItems,
                    activeKey: _activePanelKey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void navigateTo(String navKey) {
    final items = NavRegistry.all(onPush: widget.onPushRoute);
    final item = items.firstWhere(
      (i) => i.key == navKey,
      orElse: () => items.first,
    );
    _handleSelect(item, isMobile: false);
  }

  void _handleSelect(NavItem item, {required bool isMobile}) {
    if (item.behavior == NavBehavior.push) {
      if (isMobile) Navigator.of(context).pop();
      item.onPush?.call(context);
      return;
    }

    setState(() => _activePanelKey = item.key);
    if (isMobile) Navigator.of(context).pop();
  }

  String _titleForActivePanel(List<NavItem> items) {
    return items
        .firstWhere(
          (i) => i.key == _activePanelKey,
          orElse: () => items.first,
        )
        .label;
  }

  
}

class _PanelViewport extends StatelessWidget {
  final List<NavItem> panels;
  final String activeKey;

  const _PanelViewport({required this.panels, required this.activeKey});

  @override
  Widget build(BuildContext context) {
    final index = panels.indexWhere((p) => p.key == activeKey);
    final safeIndex = index < 0 ? 0 : index;

    return IndexedStack(
      index: safeIndex,
      sizing: StackFit.expand,
      children: [
        for (final panel in panels)
          KeyedSubtree(
            key: ValueKey('panel_${panel.key}'),
            child: _panelChild(context, panel),
          ),
      ],
    );
  }

  Widget _panelChild(BuildContext context, NavItem panel) {
    final registered = NavRegistry.panelBuilderFor(panel.key);
    if (registered != null) return registered(context);
    if (panel.builder != null) return panel.builder!(context);
    return _PanelPlaceholder(label: panel.label);
  }
}

class _PanelPlaceholder extends StatelessWidget {
  final String label;
  const _PanelPlaceholder({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.backgroundTop,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.construction_rounded,
            size: 48,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '$label panel',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Coming online shortly.',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}