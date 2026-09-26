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
                    // NEW
if (question.stem.isNotEmpty || question.figures.isNotEmpty)
  _RichBlock(
    text: question.stem,
    figures: question.figures,
    figureUrlResolver: figureUrlResolver,
    figureBytesResolver: figureBytesResolver,
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

    // Mode detection: same rule as the editor.
    final isSubLevelMode = part.subs.any((s) => s.marks != null);
    final isPartLevelMode = !isSubLevelMode && part.marks != null;

    // In part-level mode with subs, we render the mark at the END of
    // the part's content (below all sub-parts), right-aligned.
    // In part-level mode with no subs, we render it right after the
    // part text.
    final showPartMark = isPartLevelMode;

    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Part label + text + figures ──
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
                    if (part.text.isNotEmpty || part.figures.isNotEmpty)
                      _RichBlock(
                        text: part.text,
                        figures: part.figures,
                        figureUrlResolver: figureUrlResolver,
                        figureBytesResolver: figureBytesResolver,
                      ),
                  ],
                ),
              ),
            ],
          ),

          // ── Sub-parts ──
          // Each sub renders its own content via _RichBlock, so
          // figures appear at their exact positions.
          for (final sub in part.subs)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: _SubBlock(
                sub: sub,
                // Pass the sub's own mark — only used in sub-level mode.
                // In part-level mode, sub.marks is null anyway.
                marks: sub.marks,
                figureUrlResolver: figureUrlResolver,
                figureBytesResolver: figureBytesResolver,
              ),
            ),

          // ── Part mark — after ALL content, right-aligned ──
          if (showPartMark)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: _MarksText(value: part.marks!),
              ),
            ),
        ],
      ),
    );
  }
}

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
                    // _RichBlock handles text + figures at their
                    // marker positions in the text.
                    if (sub.text.isNotEmpty || sub.figures.isNotEmpty)
                      _RichBlock(
                        text: sub.text,
                        figures: sub.figures,
                        figureUrlResolver: figureUrlResolver,
                        figureBytesResolver: figureBytesResolver,
                      ),
                  ],
                ),
              ),
              // Sub mark, inline with the sub's first line. Only
              // rendered when the sub carries its own mark — i.e.
              // in sub-level mode.
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

class _RichBlock extends StatelessWidget {
  final String text;
  final List<PastFigureDraft> figures;
  final String? Function(PastFigureDraft fig)? figureUrlResolver;
  final Uint8List? Function(PastFigureDraft fig)? figureBytesResolver;

  const _RichBlock({
    required this.text,
    required this.figures,
    this.figureUrlResolver,
    this.figureBytesResolver,
  });

  static final _markerPattern = RegExp(r'\{\{fig:(\d+)\}\}');

  @override
  Widget build(BuildContext context) {
    final matches = _markerPattern.allMatches(text).toList();

    // Fast path — no figure markers. Either there are no figures, or
    // this is an old paper saved before positional markers existed.
    if (matches.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (text.isNotEmpty)
            AiMarkdown(
              text: text,
              style: AppTextStyles.bodyMd.copyWith(
                fontSize: 16,
                height: 1.6,
                color: AppColors.textPrimary,
              ),
            ),
          // Fallback for legacy papers: append figures at the end.
          for (final fig in figures)
            _FigureBlock(
              figure: fig,
              url: figureUrlResolver?.call(fig),
              bytes: figureBytesResolver?.call(fig),
            ),
        ],
      );
    }

    final children = <Widget>[];
    var cursor = 0;

    for (final m in matches) {
      // Text segment before this marker
      if (m.start > cursor) {
        final segment = text.substring(cursor, m.start).trim();
        if (segment.isNotEmpty) {
          children.add(
            AiMarkdown(
              text: segment,
              style: AppTextStyles.bodyMd.copyWith(
                fontSize: 16,
                height: 1.6,
                color: AppColors.textPrimary,
              ),
            ),
          );
        }
      }

      // Figure at this marker
      final idx = int.tryParse(m.group(1)!);
      if (idx != null && idx >= 0 && idx < figures.length) {
        final fig = figures[idx];
        children.add(
          _FigureBlock(
            figure: fig,
            url: figureUrlResolver?.call(fig),
            bytes: figureBytesResolver?.call(fig),
          ),
        );
      }

      cursor = m.end;
    }

    // Text after the last marker
    if (cursor < text.length) {
      final segment = text.substring(cursor).trim();
      if (segment.isNotEmpty) {
        children.add(
          AiMarkdown(
            text: segment,
            style: AppTextStyles.bodyMd.copyWith(
              fontSize: 16,
              height: 1.6,
              color: AppColors.textPrimary,
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
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

