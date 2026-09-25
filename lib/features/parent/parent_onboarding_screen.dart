import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import 'services/parent_service.dart';

/// Onboarding flow for parents.
///
/// Phase 1 — collect the parent's own details (phone, country, address).
/// Phase 2 — collect one or more student emails and send link requests.
/// Phase 3 — waiting state; shows the live status of each request and
///           allows entry to the dashboard once at least one link is
///           active.
///
/// If the parent skips onboarding, `onboarding_completed` is still
/// flipped to true so HomeScreen routes them straight to the dashboard.
class ParentOnboardingScreen extends StatefulWidget {
  const ParentOnboardingScreen({super.key});

  @override
  State<ParentOnboardingScreen> createState() =>
      _ParentOnboardingScreenState();
}

class _ParentOnboardingScreenState extends State<ParentOnboardingScreen> {
  final _service = ParentService();
  final _auth = AuthService();

  // Phase control
  int _phase = 1;   // 1 = details, 2 = emails, 3 = waiting

  // Phase 1 fields
  final _phoneController = TextEditingController();
  final _countryController = TextEditingController(text: 'Zimbabwe');
  final _addressController = TextEditingController();
  bool _savingDetails = false;

  // Phase 2 fields
  final List<_EmailEntry> _emails = [_EmailEntry()];
  bool _sendingRequests = false;

  // Phase 3 state
  List<Map<String, dynamic>> _links = const [];

  @override
  void initState() {
    super.initState();
    _loadExistingLinks();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _countryController.dispose();
    _addressController.dispose();
    for (final e in _emails) {
      e.controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadExistingLinks() async {
    final links = await _service.getMyLinks();
    if (!mounted) return;
    setState(() => _links = links);

    // If we have any link, jump straight to phase 3.
    if (links.isNotEmpty) {
      setState(() => _phase = 3);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Phase 1 — Save parent details
  // ─────────────────────────────────────────────────────────────

  Future<void> _saveDetails() async {
    final parentId = _auth.currentUserId;
    if (parentId == null) return;

    if (_phoneController.text.trim().isEmpty) {
      _snack('Please enter a phone number.', isError: true);
      return;
    }
    if (_addressController.text.trim().isEmpty) {
      _snack('Please enter an address.', isError: true);
      return;
    }

    setState(() => _savingDetails = true);
    try {
      await _service.saveParentDetails(
        parentId: parentId,
        phoneNumber: _phoneController.text.trim(),
        country: _countryController.text.trim().isEmpty
            ? null
            : _countryController.text.trim(),
        address: _addressController.text.trim(),
        onboardingCompleted: false,   // not complete until Phase 2
      );
      if (!mounted) return;
      setState(() {
        _savingDetails = false;
        _phase = 2;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingDetails = false);
      _snack('Could not save details. Please try again.', isError: true);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Phase 2 — Send student link requests
  // ─────────────────────────────────────────────────────────────

  void _addEmailField() {
    setState(() => _emails.add(_EmailEntry()));
  }

  void _removeEmailField(int index) {
    if (_emails.length <= 1) return;
    setState(() {
      _emails[index].controller.dispose();
      _emails.removeAt(index);
    });
  }

  Future<void> _sendRequests() async {
    final parentId = _auth.currentUserId;
    if (parentId == null) return;

    // Validate — every non-empty entry needs an email.
    final toSend = <_EmailEntry>[];
    for (final e in _emails) {
      final email = e.controller.text.trim();
      if (email.isEmpty) continue;
      if (!email.contains('@')) {
        _snack('"$email" is not a valid email.', isError: true);
        return;
      }
      toSend.add(e);
    }

    if (toSend.isEmpty) {
      _snack('Please enter at least one student email.', isError: true);
      return;
    }

    setState(() => _sendingRequests = true);

    final errors = <String>[];
    for (final e in toSend) {
      final err = await _service.requestLinkByEmail(
        email: e.controller.text.trim(),
        relationship: e.relationship,
      );
      if (err != null) errors.add('${e.controller.text.trim()}: $err');
    }

    // Mark onboarding complete regardless of individual failures.
    await _service.saveParentDetails(
      parentId: parentId,
      onboardingCompleted: true,
    );

    if (!mounted) return;
    setState(() => _sendingRequests = false);

    if (errors.isNotEmpty) {
      _snack(errors.join('\n'), isError: true);
    }

    // Move to phase 3 regardless.
    await _loadExistingLinks();
    if (mounted) setState(() => _phase = 3);
  }

  // ─────────────────────────────────────────────────────────────
  // Skip onboarding
  // ─────────────────────────────────────────────────────────────

  Future<void> _skip() async {
    final parentId = _auth.currentUserId;
    if (parentId == null) return;
    await _service.saveParentDetails(
      parentId: parentId,
      onboardingCompleted: true,
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  // ─────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.danger : null,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  bool get _hasActiveLink =>
      _links.any((l) => l['status'] == 'active');

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundTop,
      appBar: AppBar(
        title: const Text('Parent Setup'),
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          if (_phase != 3)
            TextButton(
              onPressed: _skip,
              child: const Text(
                'Set up later',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: AppSpacing.normal,
          child: _buildPhase(),
        ),
      ),
    );
  }

  Widget _buildPhase() {
    switch (_phase) {
      case 1:
        return _buildDetailsPhase();
      case 2:
        return _buildEmailsPhase();
      case 3:
        return _buildWaitingPhase();
      default:
        return const SizedBox.shrink();
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Phase 1 UI
  // ─────────────────────────────────────────────────────────────

  Widget _buildDetailsPhase() {
    return SingleChildScrollView(
      key: const ValueKey('phase1'),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PhaseHeader(
            step: 'Step 1 of 2',
            title: 'Your details',
            subtitle:
                'We need a way to reach you if we have to verify anything.',
          ),
          const SizedBox(height: AppSpacing.xl),

          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone number',
              hintText: '+263 77 123 4567',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          TextField(
            controller: _countryController,
            decoration: const InputDecoration(
              labelText: 'Country',
              prefixIcon: Icon(Icons.public_outlined),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          TextField(
            controller: _addressController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Address',
              hintText: 'Street, suburb, city',
              prefixIcon: Icon(Icons.home_outlined),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: _savingDetails ? null : _saveDetails,
              child: _savingDetails
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Phase 2 UI
  // ─────────────────────────────────────────────────────────────

  Widget _buildEmailsPhase() {
    return SingleChildScrollView(
      key: const ValueKey('phase2'),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PhaseHeader(
            step: 'Step 2 of 2',
            title: 'Link your children',
            subtitle:
                'Each child will receive a request in their account. They must approve before you can see their progress.',
          ),
          const SizedBox(height: AppSpacing.xl),

          for (var i = 0; i < _emails.length; i++) ...[
            _EmailFieldRow(
              entry: _emails[i],
              index: i,
              canRemove: _emails.length > 1,
              onRemove: () => _removeEmailField(i),
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          TextButton.icon(
            onPressed: _addEmailField,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add another child'),
          ),

          const SizedBox(height: AppSpacing.xl),

          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.infoBg,
              borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
              border: Border.all(color: AppColors.infoBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    size: 18, color: AppColors.info),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    "If a child doesn't respond within 48 hours, our team "
                    'will follow up to verify.',
                    style: AppTextStyles.captionXs.copyWith(
                      color: AppColors.info,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: _sendingRequests ? null : _sendRequests,
              child: _sendingRequests
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Send Requests'),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Phase 3 UI
  // ─────────────────────────────────────────────────────────────

  Widget _buildWaitingPhase() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      key: const ValueKey('phase3'),
      stream: _service.watchMyLinks(),
      builder: (context, snapshot) {
        // Fall back to local links if stream hasn't emitted yet.
        final links = snapshot.hasData && snapshot.data!.isNotEmpty
            ? snapshot.data!
            : _links;

        // Update local cache whenever new data arrives.
        if (snapshot.hasData && snapshot.data != _links) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _links = snapshot.data!);
          });
        }

        return RefreshIndicator(
          onRefresh: _loadExistingLinks,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              _PhaseHeader(
                step: 'Almost there',
                title: _hasActiveLink
                    ? 'You\'re in!'
                    : 'Waiting for approval',
                subtitle: _hasActiveLink
                    ? 'At least one of your children has approved your request. You can now open the dashboard.'
                    : 'Your children will see your request when they next open the app. This screen updates automatically.',
              ),
              const SizedBox(height: AppSpacing.xl),

              if (links.isEmpty)
                _EmptyLinksCard(onAdd: _goBackToEmails)
              else
                for (final link in links) ...[
                  _LinkStatusCard(link: link),
                  const SizedBox(height: AppSpacing.md),
                ],

              const SizedBox(height: AppSpacing.md),

              TextButton.icon(
                onPressed: _goBackToEmails,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add another child'),
              ),

              const SizedBox(height: AppSpacing.xl),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: _hasActiveLink
                      ? () => Navigator.of(context).pop(true)
                      : null,
                  child: const Text('Continue to Dashboard'),
                ),
              ),

              if (!_hasActiveLink)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Center(
                    child: Text(
                      'This button enables once a child approves.',
                      style: AppTextStyles.captionXs,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _goBackToEmails() {
    setState(() {
      _emails.clear();
      _emails.add(_EmailEntry());
      _phase = 2;
    });
  }
}

// ─────────────────────────────────────────────────────────────
// Small widgets
// ─────────────────────────────────────────────────────────────

class _PhaseHeader extends StatelessWidget {
  final String step;
  final String title;
  final String subtitle;

  const _PhaseHeader({
    required this.step,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(step.toUpperCase(), style: AppTextStyles.overline),
        const SizedBox(height: AppSpacing.sm),
        Text(title, style: AppTextStyles.displayMedium),
        const SizedBox(height: 4),
        Text(subtitle, style: AppTextStyles.bodyMd.copyWith(
          color: AppColors.textSecondary,
        )),
      ],
    );
  }
}

class _EmailEntry {
  final TextEditingController controller = TextEditingController();
  String relationship = 'mother';   // default
}

class _EmailFieldRow extends StatelessWidget {
  final _EmailEntry entry;
  final int index;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _EmailFieldRow({
    required this.entry,
    required this.index,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: entry.controller,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Student email',
                    hintText: 'child@example.com',
                    prefixIcon: Icon(Icons.person_search_outlined),
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
              if (canRemove)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove',
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text('Relationship',
                  style: AppTextStyles.captionXs.copyWith(
                    color: AppColors.textSecondary,
                  )),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: entry.relationship,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'mother', child: Text('Mother')),
                    DropdownMenuItem(value: 'father', child: Text('Father')),
                    DropdownMenuItem(
                        value: 'guardian', child: Text('Guardian')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      entry.relationship = v;
                      onChanged();
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LinkStatusCard extends StatelessWidget {
  final Map<String, dynamic> link;
  const _LinkStatusCard({required this.link});

  String get _studentName {
    final student = link['student'] as Map<String, dynamic>?;
    if (student == null) return 'Student';
    final display = student['display_name'] as String?;
    if (display != null && display.isNotEmpty) return display;
    return student['full_name'] as String? ?? 'Student';
  }

  String get _initials {
    final name = _studentName.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  ({Color bg, Color border, Color fg, IconData icon, String label})
      get _statusVisuals {
    switch (link['status']) {
      case 'active':
        return (
          bg: AppColors.successBg,
          border: AppColors.successBorder,
          fg: AppColors.success,
          icon: Icons.check_circle_rounded,
          label: 'Approved',
        );
      case 'denied':
        return (
          bg: AppColors.dangerBg,
          border: AppColors.dangerBorder,
          fg: AppColors.danger,
          icon: Icons.cancel_rounded,
          label: 'Declined',
        );
      default:
        return (
          bg: AppColors.warningBg,
          border: AppColors.warningBorder,
          fg: AppColors.warning,
          icon: Icons.schedule_rounded,
          label: 'Pending',
        );
    }
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
              _initials,
              style: AppTextStyles.labelMd.copyWith(color: Colors.white),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_studentName, style: AppTextStyles.labelMd),
                const SizedBox(height: 2),
                Text(
                  link['relationship']?.toString() ?? '',
                  style: AppTextStyles.captionXs,
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
        ],
      ),
    );
  }
}

class _EmptyLinksCard extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyLinksCard({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(Icons.link_off_rounded,
              size: 40, color: AppColors.textTertiary),
          const SizedBox(height: AppSpacing.md),
          Text('No requests yet',
              style: AppTextStyles.headingMd),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Add a child to send a link request.',
            style: AppTextStyles.caption,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add a child'),
          ),
        ],
      ),
    );
  }
}