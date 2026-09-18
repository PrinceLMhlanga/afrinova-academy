import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../models/analytics_kpis.dart';
import 'kpi_card.dart';

/// The top row of headline stats.
///
/// Seven metrics from [AnalyticsKpis], laid out responsively:
///   • Mobile  (< 600px) — 2 columns
///   • Tablet  (600–1000px) — 3 columns
///   • Desktop (>= 1000px) — 4 columns, wrapping to a second row for the
///     final three cards.
///
/// Implementation note: we use a [Wrap] with fixed-width cards rather
/// than [GridView], so partial rows left-align naturally instead of
/// being centered or stretched.
class KpiRow extends StatelessWidget {
  final AnalyticsKpis kpis;

  const KpiRow({super.key, required this.kpis});

  @override
  Widget build(BuildContext context) {
    final cards = _buildCards(kpis);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width < 600
            ? 2
            : width < 1000
                ? 3
                : 4;

        const gap = AppSpacing.md;
        final totalGap = gap * (columns - 1);
        final cardWidth = (width - totalGap) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards)
              SizedBox(width: cardWidth, child: card),
          ],
        );
      },
    );
  }

    List<Widget> _buildCards(AnalyticsKpis k) {
    final cards = <Widget>[
      KpiCard(
        index: 0,
        icon: Icons.auto_awesome_rounded,
        accent: AppColors.chartAi,
        label: 'AI Exam Avg',
        value: k.aiExamAvg != null ? '${k.aiExamAvg!.toStringAsFixed(1)}%' : null,
      ),
      KpiCard(
        index: 1,
        icon: Icons.style_rounded,
        accent: const Color(0xFF8B5CF6),
        label: 'Flashcards Mastered',
        value: k.flashcardsTotal == 0 ? null : '${k.flashcardsMastered}',
        footer: k.flashcardsTotal == 0
            ? 'No cards reviewed yet'
            : 'of ${k.flashcardsTotal} reviewed',
      ),
      KpiCard(
        index: 2,
        icon: Icons.flag_rounded,
        accent: const Color(0xFF0EA5E9),
        label: 'Objectives Mastered',
        value: k.objectivesTotal == 0 ? null : '${k.objectivesMastered}',
        footer: k.objectivesTotal == 0
            ? 'No objectives yet'
            : 'of ${k.objectivesTotal}',
      ),
      KpiCard(
        index: 3,
        icon: Icons.assignment_turned_in_rounded,
        accent: AppColors.chartPaper,
        label: 'Exam Paper Avg',
        value: k.examPaperAvg != null
            ? '${k.examPaperAvg!.toStringAsFixed(1)}%'
            : null,
        footer: k.papersAttempted == 0
            ? 'No papers marked'
            : '${k.papersAttempted} paper${k.papersAttempted == 1 ? '' : 's'}',
      ),
      KpiCard(
        index: 4,
        icon: Icons.quiz_rounded,
        accent: AppColors.chartMcq,
        label: 'MCQ Score',
        value: k.mcqAvg != null ? '${k.mcqAvg!.toStringAsFixed(0)}%' : null,
        footer: k.mcqAvg == null ? 'Not attempted' : null,
      ),
      KpiCard(
        index: 5,
        icon: Icons.play_circle_outline_rounded,
        accent: const Color(0xFFEC4899),
        label: 'Lessons Completed',
        value: k.lessonsCompleted == 0 ? null : '${k.lessonsCompleted}',
      ),
      KpiCard(
        index: 6,
        icon: Icons.description_outlined,
        accent: const Color(0xFF14B8A6),
        label: 'Papers Attempted',
        value: k.papersAttempted == 0 ? null : '${k.papersAttempted}',
      ),
    ];
    return cards;
  }
}