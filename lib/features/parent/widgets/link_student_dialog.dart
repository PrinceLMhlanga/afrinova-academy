import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../services/parent_service.dart';

/// Dialog that lets a parent send a new link request to a student.
///
/// Used from the onboarding Phase 2 screen and from the Children
/// panel. Returns true via Navigator.pop when a request was sent.
class LinkStudentDialog extends StatefulWidget {
  const LinkStudentDialog({super.key});

  @override
  State<LinkStudentDialog> createState() => _LinkStudentDialogState();
}

class _LinkStudentDialogState extends State<LinkStudentDialog> {
  final _controller = TextEditingController();
  final _service = ParentService();

  String _relationship = 'mother';
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _controller.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter an email.');
      return;
    }
    if (!email.contains('@')) {
      setState(() => _error = 'Enter a valid email.');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    final err = await _service.requestLinkByEmail(
      email: email,
      relationship: _relationship,
    );

    if (!mounted) return;

    if (err == null) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _sending = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Link a Student'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your child\'s email. They\'ll receive a request '
              'and must approve it before you can see their progress.',
              style: AppTextStyles.bodySm,
            ),
            const SizedBox(height: AppSpacing.lg),

            TextField(
              controller: _controller,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Student email',
                hintText: 'child@example.com',
                prefixIcon: Icon(Icons.person_search_outlined),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            DropdownButtonFormField<String>(
              value: _relationship,
              decoration: const InputDecoration(
                labelText: 'Relationship',
                prefixIcon: Icon(Icons.family_restroom_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'mother', child: Text('Mother')),
                DropdownMenuItem(value: 'father', child: Text('Father')),
                DropdownMenuItem(value: 'guardian', child: Text('Guardian')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: _sending
                  ? null
                  : (v) {
                      if (v != null) {
                        setState(() => _relationship = v);
                      }
                    },
            ),

            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.dangerBg,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusChip),
                  border: Border.all(color: AppColors.dangerBorder),
                ),
                child: Text(
                  _error!,
                  style: AppTextStyles.captionXs.copyWith(
                    color: AppColors.danger,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _sending ? null : _submit,
          child: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send Request'),
        ),
      ],
    );
  }
}