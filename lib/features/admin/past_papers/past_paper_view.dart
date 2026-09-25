import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../widgets/ai_markdown.dart';
import 'past_paper_parser.dart';

/// Renders a single question in exam-paper style.
///
/// Layout follows the printed format:
///   * Question number on the left
///   * Text flowing on the right
///   * Part labels as (a), (b), (c) — never "PART"
///   * Sub-part labels as (i), (ii), (iii)
///   * Marks right-aligned at the end of the part's last child
///   * Figures rendered below the text that references them
///
/// This widget is display-only. It is reused by the admin import
/// preview and (later) the student exam-taker screen.
class PaperQuestionView extends StatelessWidget {
  final PastQuestionDraft question;

  /// Optional: URL resolver for a figure caption → display URL.
  /// If null, figures render as a "figure pending" placeholder.
  final String? Function(PastFigureDraft fig)? figureUrlResolver;
  final Uint8List? Function(PastFigureDraft fig)? figureBytesResolver; 
  

  const PaperQuestionView({
    super.key,
    required this.question,
    this.figureUrlResolver,
    this.figureBytesResolver,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question number + stem (if any)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Fixed-width number column
              SizedBox(
                width: 32,
                child: Text(
                  '${question.number}',
                  style: AppTextStyles.headingSm.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (question.stem.isNotEmpty)
                      _MarkdownBlock(text: question.stem),
                    // Stem figures
                    for (final fig in question.figures)
                      _FigureBlock(
                        figure: fig,
                        url: figureUrlResolver?.call(fig),
                        bytes: figureBytesResolver?.call(fig),
                      ),
                  ],
                ),
              ),
            ],
          ),

                    // Parts
          for (final part in question.parts)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: _PartBlock(
                part: part,
                figureUrlResolver: figureUrlResolver,
                figureBytesResolver: figureBytesResolver,
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Part
// ─────────────────────────────────────────────────────────────

class _PartBlock extends StatelessWidget {
  final PastPartDraft part;
  final String? Function(PastFigureDraft fig)? figureUrlResolver;
  final Uint8List? Function(PastFigureDraft fig)? figureBytesResolver;

  const _PartBlock({
    required this.part,
    this.figureUrlResolver,
    this.figureBytesResolver,
  });

  @override
  Widget build(BuildContext context) {
    const labelWidth = 40.0;
    final marksOnThisPart = part.marks != null && part.subs.isEmpty;

    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: labelWidth,
                child: Text(
                  '(${part.label})',
                  style: AppTextStyles.bodyMd.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (part.text.isNotEmpty)
                      _MarkdownBlock(text: part.text),
                    for (final fig in part.figures)
                      _FigureBlock(
                        figure: fig,
                        url: figureUrlResolver?.call(fig),
                        bytes: figureBytesResolver?.call(fig),
                      ),
                  ],
                ),
              ),
            ],
          ),

          for (var i = 0; i < part.subs.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: _SubBlock(
                sub: part.subs[i],
                marks: (i == part.subs.length - 1 && part.marks != null)
                    ? part.marks
                    : null,
                figureUrlResolver: figureUrlResolver,
                figureBytesResolver: figureBytesResolver,
              ),
            ),

          if (marksOnThisPart)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _MarksText(value: part.marks!),
              ),
            ),
        ],
      ),
    );
  }
}
// ─────────────────────────────────────────────────────────────
// Sub-part
// ─────────────────────────────────────────────────────────────

class _SubBlock extends StatelessWidget {
  final PastSubDraft sub;
  final int? marks;
  final String? Function(PastFigureDraft fig)? figureUrlResolver;
  final Uint8List? Function(PastFigureDraft fig)? figureBytesResolver;

  const _SubBlock({
    required this.sub,
    this.marks,
    this.figureUrlResolver,
    this.figureBytesResolver,
  });

  @override
  Widget build(BuildContext context) {
    const labelWidth = 44.0;

    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: labelWidth,
                child: Text(
                  '(${sub.label})',
                  style: AppTextStyles.bodyMd.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (sub.text.isNotEmpty)
                      _MarkdownBlock(text: sub.text),
                    for (final fig in sub.figures)
                      _FigureBlock(
                        figure: fig,
                        url: figureUrlResolver?.call(fig),
                      ),
                  ],
                ),
              ),
              // Marks right-aligned on the first line, if present.
              if (marks != null)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.sm),
                  child: _MarksText(value: marks!),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Shared bits
// ─────────────────────────────────────────────────────────────

class _MarksText extends StatelessWidget {
  final int value;
  const _MarksText({required this.value});

  @override
  Widget build(BuildContext context) {
    return Text(
      '[$value]',
      style: AppTextStyles.bodyMd.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _MarkdownBlock extends StatelessWidget {
  final String text;
  const _MarkdownBlock({required this.text});

  @override
  Widget build(BuildContext context) {
    return AiMarkdown(
      text: text,
      style: AppTextStyles.bodyMd.copyWith(
        fontSize: 16,
        height: 1.6,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _FigureBlock extends StatelessWidget {
  final PastFigureDraft figure;
  final String? url;
  final Uint8List? bytes;

  const _FigureBlock({
    required this.figure,
    this.url,
    this.bytes,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Priority: in-memory bytes > network url > placeholder.
          if (bytes != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusChip),
              child: Image.memory(
                bytes!,
                fit: BoxFit.contain,
              ),
            )
          else if (url != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusChip),
              child: Image.network(
                url!,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    _FigurePlaceholder(caption: figure.caption),
              ),
            )
          else
            _FigurePlaceholder(caption: figure.caption),

          if (figure.caption != null) ...[
            const SizedBox(height: 6),
            Text(
              figure.caption!,
              style: AppTextStyles.captionXs.copyWith(
                fontStyle: FontStyle.italic,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FigurePlaceholder extends StatelessWidget {
  final String? caption;
  const _FigurePlaceholder({this.caption});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppSpacing.radiusChip),
        border: Border.all(
          color: AppColors.border,
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.image_outlined,
            size: 28,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 6),
          Text(
            caption != null ? 'Figure: $caption' : 'Figure pending',
            style: AppTextStyles.captionXs.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Full paper renderer
// ─────────────────────────────────────────────────────────────

/// Renders a whole paper: metadata header, sections with notes,
/// then each question in order.
class PaperView extends StatelessWidget {
  final PastPaperDraft paper;

  /// Optional: provide a metadata block above the questions
  /// (paper title, subject, duration, instructions).
  final bool showHeader;

  /// Optional: resolve a figure to a URL. Called per-figure.
  final String? Function(PastFigureDraft fig)? figureUrlResolver;
  final Uint8List? Function(PastFigureDraft fig)? figureBytesResolver;

  const PaperView({
    super.key,
    required this.paper,
    this.showHeader = true,
    this.figureUrlResolver,
    this.figureBytesResolver,
  });

  @override
  Widget build(BuildContext context) {
    // Group questions by section so we can insert section headers.
    final sections = <String, List<PastQuestionDraft>>{};
    for (final q in paper.questions) {
      final key = q.section ?? '';
      sections.putIfAbsent(key, () => []).add(q);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader && paper.title != null)
          _PaperHeader(paper: paper),

        for (final entry in sections.entries) ...[
          if (entry.key.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            _SectionHeader(
              name: entry.key,
              note: paper.sectionNotes[entry.key],
            ),
          ],
          for (final q in entry.value)
            PaperQuestionView(
              question: q,
              figureUrlResolver: figureUrlResolver,
              figureBytesResolver: figureBytesResolver,
            ),
        ],
      ],
    );
  }
}

class _PaperHeader extends StatelessWidget {
  final PastPaperDraft paper;
  const _PaperHeader({required this.paper});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (paper.title != null)
            Text(
              paper.title!,
              textAlign: TextAlign.center,
              style: AppTextStyles.headingLg,
            ),
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.md,
            children: [
              if (paper.subjectName != null)
                _MetaChip(text: paper.subjectName!),
              if (paper.levelName != null)
                _MetaChip(text: paper.levelName!),
              if (paper.paperType != null)
                _MetaChip(text: paper.paperType!),
              if (paper.year != null)
                _MetaChip(text: '${paper.year}'),
              if (paper.session != null)
                _MetaChip(text: paper.session!),
              if (paper.durationMinutes != null)
                _MetaChip(text: '${paper.durationMinutes} min'),
            ],
          ),
          if (paper.instructions != null) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(),
            const SizedBox(height: AppSpacing.sm),
            Text(
              paper.instructions!,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySm,
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String name;
  final String? note;

  const _SectionHeader({required this.name, this.note});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            name,
            textAlign: TextAlign.center,
            style: AppTextStyles.headingMd.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 2),
            Text(
              note!,
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String text;
  const _MetaChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.caption.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );
  }
}

