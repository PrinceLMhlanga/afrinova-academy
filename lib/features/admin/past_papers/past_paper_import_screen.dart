import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/shell/shell_app_bar.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import 'past_paper_parser.dart';
import 'past_paper_service.dart';
import 'package:flutter/services.dart';
import 'past_paper_view.dart';

class PastPaperImportScreen extends StatefulWidget {
  const PastPaperImportScreen({super.key});

  @override
  State<PastPaperImportScreen> createState() => _PastPaperImportScreenState();
}

class _PastPaperImportScreenState extends State<PastPaperImportScreen> {
  final _service = PastPaperService();
  final _parser = PastPaperParser();
  final _rawController = TextEditingController();

  // Metadata
  String? _subjectId;
  String? _levelId;
  String? _paperType;
  int? _year;
  String? _session;
  String? _source;
  int? _durationMinutes;
  final _titleController = TextEditingController();
  final _instructionsController = TextEditingController();

  // Loaded from DB
  List<Map<String, dynamic>> _subjects = const [];
  List<Map<String, dynamic>> _levels = const [];
  List<Map<String, dynamic>> _topics = const [];
  bool _loadingMeta = true;

    // Parse output
  PastPaperParseResult? _parsed;

  // Warnings from parse + resolution steps
  final List<String> _parseWarnings = [];

  // Per-question topic selection: question number → topic id
  final Map<int, String?> _topicByQuestion = {};

  
  // Figure locator → bytes. Locator format: "q1.stem.0", "q1.part.a.0",
// "q1.part.c.sub.ii.1", etc.
final Map<String, Uint8List> _figureBytes = {};

  bool _saving = false;

    bool _showPreviewPane = true;
  double _previewPaneWidth = 480;   // pixels; updated by the drag handle

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  @override
  void dispose() {
    _rawController.dispose();
    _titleController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    try {
      final results = await Future.wait([
        _service.getSubjects(),
        _service.getLevels(),
      ]);
      if (!mounted) return;
      setState(() {
        _subjects = results[0];
        _levels = results[1];
        _loadingMeta = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingMeta = false);
    }
  }

  Future<void> _loadTopics() async {
    if (_subjectId == null || _levelId == null) {
      setState(() => _topics = const []);
      return;
    }
    final res = await _service.getTopicsFor(
      subjectId: _subjectId!,
      levelId: _levelId!,
    );
    if (!mounted) return;
    setState(() => _topics = res);
  }

    /// After topics are loaded, walk the parsed questions and resolve
  /// each one's topicIndex or topicName to an actual topic id.
  /// Emits warnings for unresolved names.
  void _resolveQuestionTopics() {
    final questions = _parsed?.paper.questions ?? const [];
    final warnings = <String>[];

    for (final q in questions) {
      // Priority 1 — numeric index into the loaded topic list
      if (q.topicIndex != null &&
          q.topicIndex! > 0 &&
          q.topicIndex! <= _topics.length) {
        _topicByQuestion[q.number] = _topics[q.topicIndex! - 1]['id'] as String;
        continue;
      }

      // Priority 2 — exact case-insensitive name match
      if (q.topicName != null && q.topicName!.trim().isNotEmpty) {
        final wanted = q.topicName!.toLowerCase().trim();
        Map<String, dynamic> match = {};
        for (final t in _topics) {
          if ((t['name'] as String).toLowerCase().trim() == wanted) {
            match = t;
            break;
          }
        }
        if (match.isNotEmpty) {
          _topicByQuestion[q.number] = match['id'] as String;
        } else {
          warnings.add(
            'Q${q.number}: topic "${q.topicName}" not found in the topic list.',
          );
        }
      }
    }

    if (mounted) {
      setState(() => _parseWarnings.addAll(warnings));
    }
  }

  

    Future<void> _parse() async {
    final raw = _rawController.text;
    if (raw.trim().isEmpty) return;

    final result = _parser.parse(raw);

    // Reset any previous resolution warnings.
    _parseWarnings.clear();
    _topicByQuestion.clear();

    // ── Resolve subject name → subject_id ──
    String? resolvedSubjectId = _subjectId;
    if (result.paper.subjectName != null) {
      final wanted = result.paper.subjectName!.toLowerCase().trim();
      for (final s in _subjects) {
        if ((s['name'] as String).toLowerCase().trim() == wanted) {
          resolvedSubjectId = s['id'] as String;
          break;
        }
      }
      if (resolvedSubjectId == _subjectId) {
        _parseWarnings.add(
          'Subject "${result.paper.subjectName}" not found in the subjects list.',
        );
      }
    }

    // ── Resolve level name → level_id ──
    String? resolvedLevelId = _levelId;
    if (result.paper.levelName != null) {
      final wanted = result.paper.levelName!.toLowerCase().trim();
      for (final l in _levels) {
        if ((l['name'] as String).toLowerCase().trim() == wanted) {
          resolvedLevelId = l['id'] as String;
          break;
        }
      }
      if (resolvedLevelId == _levelId) {
        _parseWarnings.add(
          'Level "${result.paper.levelName}" not found in the levels list.',
        );
      }
    }

    // ── Commit the parsed paper and any resolved metadata ──
    setState(() {
      _parsed = result;
      _subjectId = resolvedSubjectId;
      _levelId = resolvedLevelId;

      if (_titleController.text.isEmpty && result.paper.title != null) {
        _titleController.text = result.paper.title!;
      }
      if (_paperType == null && result.paper.paperType != null) {
        _paperType = result.paper.paperType;
      }
      if (_year == null && result.paper.year != null) {
        _year = result.paper.year;
      }
      if (_session == null && result.paper.session != null) {
        _session = result.paper.session;
      }
      if (_source == null && result.paper.source != null) {
        _source = result.paper.source;
      }
      if (_durationMinutes == null && result.paper.durationMinutes != null) {
        _durationMinutes = result.paper.durationMinutes;
      }
      if (_instructionsController.text.isEmpty &&
          result.paper.instructions != null) {
        _instructionsController.text = result.paper.instructions!;
      }
    });

    // ── Load topics if we now have subject + level, then resolve ──
    if (_subjectId != null && _levelId != null) {
      await _loadTopics();
      _resolveQuestionTopics();
    }
  }

    void _openStandalonePreview() {
  if (_parsed == null) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: AppColors.backgroundTop,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(AppSpacing.topbarHeight),
          child: ShellAppBar(
            title: 'Paper Preview',
            onBack: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: PaperView(
            paper: _parsed!.paper,
            figureUrlResolver: (_) => null,
            figureBytesResolver: (fig) => _figureBytes[fig.locator],
          ),
        ),
      ),
    ),
  );
}
    void _updateQuestionMarks(int qNum, int? marks) {
    final parsed = _parsed;
    if (parsed == null) return;
    final q = parsed.paper.questions.firstWhere(
      (x) => x.number == qNum,
      orElse: () => parsed.paper.questions.first,
    );
    setState(() => q.marks = marks);
  }

  /// Recompute a question's marks from its parts/subs.
/// Priority: sum of part marks if any part has marks;
/// otherwise sum of sub marks across all parts.
int? _computeQuestionMarks(PastQuestionDraft q) {
  if (q.parts.isNotEmpty) {
    final partSum = q.parts
        .where((p) => p.marks != null)
        .fold<int>(0, (a, b) => a + (b.marks ?? 0));
    if (partSum > 0) return partSum;

    final subSum = q.parts
        .expand((p) => p.subs)
        .where((s) => s.marks != null)
        .fold<int>(0, (a, b) => a + (b.marks ?? 0));
    if (subSum > 0) return subSum;
  }
  return null;
}

void _updatePartMarks(int qNum, String partLabel, int? marks) {
  final parsed = _parsed;
  if (parsed == null) return;
  final q = parsed.paper.questions.firstWhere(
    (x) => x.number == qNum,
    orElse: () => parsed.paper.questions.first,
  );
  final p = q.parts.firstWhere(
    (x) => x.label == partLabel,
    orElse: () => q.parts.first,
  );
  setState(() {
    p.marks = marks;
    // If we now have a part-level mark, clear sub marks so we
    // don't end up with a mixed pattern.
    if (marks != null) {
      for (final s in p.subs) {
        s.marks = null;
      }
    }
    q.marks = _computeQuestionMarks(q);
  });
}

void _updateSubMarks(
  int qNum,
  String partLabel,
  String subLabel,
  int? marks,
) {
  final parsed = _parsed;
  if (parsed == null) return;
  final q = parsed.paper.questions.firstWhere(
    (x) => x.number == qNum,
    orElse: () => parsed.paper.questions.first,
  );
  final p = q.parts.firstWhere(
    (x) => x.label == partLabel,
    orElse: () => q.parts.first,
  );
  final s = p.subs.firstWhere(
    (x) => x.label == subLabel,
    orElse: () => p.subs.first,
  );
  setState(() {
    s.marks = marks;
    if (marks != null) {
      // Setting a sub mark implies the part should have no mark.
      p.marks = null;
    }
    q.marks = _computeQuestionMarks(q);
  });
}

  Future<void> _save({required bool publish}) async {
    if (_parsed == null) return;
    if (_subjectId == null || _levelId == null) {
      _showSnack('Pick a subject and level first.');
      return;
    }
    if (_titleController.text.trim().isEmpty) {
      _showSnack('Give the paper a title.');
      return;
    }

    setState(() => _saving = true);

    try {
      final topicMap = <int, String>{};
      _topicByQuestion.forEach((q, t) {
        if (t != null) topicMap[q] = t;
      });

     final paperId = await _service.savePaper(
  paper: _parsed!.paper,
  subjectId: _subjectId!,
  levelId: _levelId!,
  title: _titleController.text.trim(),
  paperType: _paperType ?? 'Paper 1',
  year: _year ?? DateTime.now().year,
  session: _session ?? 'November',
  source: _source ?? 'ZIMSEC',
  durationMinutes: _durationMinutes ?? 120,
  instructions: _instructionsController.text.trim().isEmpty
      ? null
      : _instructionsController.text.trim(),
  topicByQuestion: topicMap,
  figureBytes: _figureBytes,   // ← renamed
  rawTranscript: _rawController.text,
  publish: publish,
);

      if (!mounted) return;
      _showSnack(publish ? 'Paper published.' : 'Draft saved.');
      Navigator.of(context).pop(paperId);
    } catch (e) {
      if (mounted) _showSnack('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

 @override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: AppColors.backgroundTop,
    appBar: PreferredSize(
  preferredSize: const Size.fromHeight(AppSpacing.topbarHeight),
  child: ShellAppBar(
    title: 'Import Past Paper',
    onBack: () => Navigator.of(context).maybePop(),
    actions: [
      // ── Preview toggle ──
      if (_parsed != null)
        IconButton(
          icon: Icon(
            _showPreviewPane
                ? Icons.visibility_rounded
                : Icons.visibility_outlined,
            size: 20,
          ),
          color: Colors.white,
          tooltip: _showPreviewPane ? 'Hide preview' : 'Show preview',
          onPressed: () {
            final isWide = MediaQuery.sizeOf(context).width >= 1000;
            if (isWide) {
              setState(() => _showPreviewPane = !_showPreviewPane);
            } else {
              _openStandalonePreview();
            }
          },
        ),

      // ── Save Draft ──
      TextButton(
        onPressed: _saving || _parsed == null
            ? null
            : () => _save(publish: false),
        child: Text(
          'Save Draft',
          style: AppTextStyles.labelMd.copyWith(
            color: Colors.white.withOpacity(
              _saving || _parsed == null ? 0.4 : 1.0,
            ),
          ),
        ),
      ),
      const SizedBox(width: 4),

      // ── Publish ──
      FilledButton(
        onPressed: _saving || _parsed == null
            ? null
            : () => _save(publish: true),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
        ),
        child: _saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Publish'),
      ),
    ],
  ),
),
    body: _loadingMeta
        ? const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          )
        : _buildBody(),
  );
}

    Widget _buildBody() {
    final isWide = MediaQuery.sizeOf(context).width >= 1000;

    // Narrow screens or preview toggled off: single column.
    if (!isWide || !_showPreviewPane || _parsed == null) {
      return _buildEditorColumn();
    }

    // Wide screens with preview on: split pane with draggable divider.
    return LayoutBuilder(
      builder: (context, constraints) {
        const dividerWidth = 10.0;
        final totalWidth = constraints.maxWidth;
        final maxPreview = totalWidth * 0.75;
        final minPreview = totalWidth * 0.30;

        final previewWidth =
            _previewPaneWidth.clamp(minPreview, maxPreview).toDouble();
        final editorWidth = totalWidth - previewWidth - dividerWidth;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: editorWidth,
              child: _buildEditorColumn(),
            ),
            _DragHandle(
              onDrag: (dx) {
                setState(() {
                  _previewPaneWidth =
                      (previewWidth - dx).clamp(minPreview, maxPreview);
                });
              },
            ),
            SizedBox(
              width: previewWidth,
              child: _buildPreviewPane(),
            ),
          ],
        );
      },
    );
  }

    Widget _buildEditorColumn() {
  return ListView(
    padding: const EdgeInsets.all(AppSpacing.xl),
    children: [
      _buildMetadataCard(),
      const SizedBox(height: AppSpacing.lg),
      _buildPasteCard(),
      if (_parsed != null) ...[
        const SizedBox(height: AppSpacing.lg),
        _buildPreviewCard(),
      ],
    ],
  );
}

    Widget _buildPreviewPane() {
  if (_parsed == null) {
    return Container(
      color: AppColors.backgroundBottom,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.description_outlined,
            size: 40,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Parse a paper to see the preview',
            style: AppTextStyles.bodySm,
          ),
        ],
      ),
    );
  }

  return Container(
    color: AppColors.backgroundBottom,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: PaperView(
        paper: _parsed!.paper,
        figureUrlResolver: (_) => null,
        figureBytesResolver: (fig) => _figureBytes[fig.locator],   // NEW
      ),
    ),
  );
}

  Widget _buildMetadataCard() {
    return _Card(
      title: 'Paper Metadata',
      subtitle: 'These apply to the whole paper.',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _Dropdown(
                  label: 'Subject',
                  value: _subjectId,
                  items: _subjects
                      .map((s) => DropdownMenuItem(
                            value: s['id'] as String,
                            child: Text(s['name'] as String),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _subjectId = v);
                    _loadTopics();
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _Dropdown(
                  label: 'Level',
                  value: _levelId,
                  items: _levels
                      .map((l) => DropdownMenuItem(
                            value: l['id'] as String,
                            child: Text(l['name'] as String),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _levelId = v);
                    _loadTopics();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'Chemistry Paper 3 — November 2018',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _Dropdown(
                  label: 'Paper Type',
                  value: _paperType,
                  items: const [
                    DropdownMenuItem(value: 'Paper 1', child: Text('Paper 1')),
                    DropdownMenuItem(value: 'Paper 2', child: Text('Paper 2')),
                    DropdownMenuItem(value: 'Paper 3', child: Text('Paper 3')),
                    DropdownMenuItem(value: 'Section A', child: Text('Section A')),
                    DropdownMenuItem(value: 'Section B', child: Text('Section B')),
                  ],
                  onChanged: (v) => setState(() => _paperType = v),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Year'),
                  keyboardType: TextInputType.number,
                  controller: TextEditingController(text: _year?.toString() ?? ''),
                  onChanged: (v) => _year = int.tryParse(v),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _Dropdown(
                  label: 'Session',
                  value: _session,
                  items: const [
                    DropdownMenuItem(value: 'June', child: Text('June')),
                    DropdownMenuItem(value: 'November', child: Text('November')),
                  ],
                  onChanged: (v) => setState(() => _session = v),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _Dropdown(
                  label: 'Source',
                  value: _source,
                  items: const [
                    DropdownMenuItem(value: 'ZIMSEC', child: Text('ZIMSEC')),
                    DropdownMenuItem(value: 'Cambridge', child: Text('Cambridge')),
                    DropdownMenuItem(value: 'Mock', child: Text('Mock')),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (v) => setState(() => _source = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Duration (minutes)',
            ),
            keyboardType: TextInputType.number,
            controller:
                TextEditingController(text: _durationMinutes?.toString() ?? ''),
            onChanged: (v) => _durationMinutes = int.tryParse(v),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _instructionsController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Instructions (optional)',
              hintText: 'Answer any two questions from this section...',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasteCard() {
    return _Card(
      title: 'DeepSeek Output',
      subtitle: 'Paste the transcription below, then tap Parse.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_topics.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: OutlinedButton.icon(
                onPressed: _copyTopicList,
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: Text('Copy numbered topic list (${_topics.length} topics)'),
              ),
            ),
          TextField(
            controller: _rawController,
            maxLines: 12,
            minLines: 8,
            style: AppTextStyles.bodySm.copyWith(
              fontFamily: 'monospace',
              height: 1.4,
            ),
            decoration: const InputDecoration(
              hintText: 'Paste DeepSeek output here...',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _parse,
                icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                label: const Text('Parse'),
              ),
              const SizedBox(width: AppSpacing.sm),
                            if (_parsed != null)
                TextButton(
                  onPressed: () => setState(() {
                    _parsed = null;
                    _parseWarnings.clear();
                    _topicByQuestion.clear();
                    _figureBytes.clear();
                  }),
                  child: const Text('Clear preview'),
                ),
            ],
          ),
                    if (_parsed != null &&
              (_parsed!.errors.isNotEmpty || _parseWarnings.isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: _ParseWarnings(
                errors: [
                  ..._parsed!.errors,
                  ..._parseWarnings,
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _copyTopicList() async {
    final buffer = StringBuffer();
    for (var i = 0; i < _topics.length; i++) {
      buffer.writeln('${i + 1}. ${_topics[i]['name']}');
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) _showSnack('Topic list copied.');
  }

  Widget _buildPreviewCard() {
    final paper = _parsed!.paper;
    return _Card(
      title: 'Preview · ${paper.questions.length} questions',
      subtitle:
          'Review each question, pick a topic, and attach figures where marked.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < paper.questions.length; i++) ...[
  _QuestionPreviewCard(
    question: paper.questions[i],
    questionIndex: i,
    topics: _topics,
    selectedTopicId: _topicByQuestion[paper.questions[i].number],
    onTopicChanged: (id) => setState(
        () => _topicByQuestion[paper.questions[i].number] = id),
    figureBytes: _figureBytes,
    onFigureChanged: (locator, bytes) => setState(() {
      if (bytes == null) {
        _figureBytes.remove(locator);
      } else {
        _figureBytes[locator] = bytes;
      }
    }),
    onQuestionMarksChanged: _updateQuestionMarks,
    onPartMarksChanged: _updatePartMarks,
    onSubMarksChanged: _updateSubMarks,
  ),
  const SizedBox(height: AppSpacing.md),
],
        ],
      ),
    );
  }
}

class _DragHandle extends StatefulWidget {
  final void Function(double dx) onDrag;
  const _DragHandle({required this.onDrag});

  @override
  State<_DragHandle> createState() => _DragHandleState();
}

class _DragHandleState extends State<_DragHandle> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        child: Container(
          width: 10,
          color: _dragging || _hovered
              ? AppColors.primary.withOpacity(0.12)
              : AppColors.border,
          child: Center(
            child: Container(
              width: 2,
              height: 48,
              decoration: BoxDecoration(
                color: _dragging || _hovered
                    ? AppColors.primary
                    : AppColors.textTertiary,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Placeholder sub-widgets — to be expanded
// ─────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const _Card({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.headingMd),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: AppTextStyles.captionXs),
          ],
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }
}

class _Dropdown extends StatelessWidget {
  final String label;
  final String? value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;

  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(labelText: label),
      items: items,
      onChanged: onChanged,
    );
  }
}

class _ParseWarnings extends StatelessWidget {
  final List<String> errors;
  const _ParseWarnings({required this.errors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
        border: Border.all(color: AppColors.warningBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Warnings',
            style: AppTextStyles.labelMd.copyWith(color: AppColors.warning),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final e in errors)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• $e', style: AppTextStyles.caption),
            ),
        ],
      ),
    );
  }
}

class _QuestionPreviewCard extends StatelessWidget {
  final PastQuestionDraft question;
  final int questionIndex;
  final List<Map<String, dynamic>> topics;
  final String? selectedTopicId;
  final ValueChanged<String?> onTopicChanged;
  final Map<String, Uint8List> figureBytes;
  final void Function(String locator, Uint8List? bytes) onFigureChanged;

  // Mark editing callbacks
  final void Function(int qNum, int? marks) onQuestionMarksChanged;
  final void Function(int qNum, String partLabel, int? marks)
      onPartMarksChanged;
  final void Function(int qNum, String partLabel, String subLabel, int? marks)
      onSubMarksChanged;

  const _QuestionPreviewCard({
    required this.question,
    required this.questionIndex,
    required this.topics,
    required this.selectedTopicId,
    required this.onTopicChanged,
    required this.figureBytes,
    required this.onFigureChanged,
    required this.onQuestionMarksChanged,
    required this.onPartMarksChanged,
    required this.onSubMarksChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
  children: [
    Text('Q${question.number}', style: AppTextStyles.headingSm),
    if (question.marks != null) ...[
      const SizedBox(width: AppSpacing.sm),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.06),
          borderRadius: BorderRadius.circular(AppSpacing.radiusChip),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.15),
          ),
        ),
        child: Text(
          '[${question.marks}]',
          style: AppTextStyles.caption.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
      ),
    ],
    if (question.section != null) ...[
      const SizedBox(width: AppSpacing.sm),
      _Pill(text: question.section!),
    ],
  ],
),
          const SizedBox(height: AppSpacing.sm),

          if (question.stem.isNotEmpty)
            Text(question.stem, style: AppTextStyles.bodySm),

          // In _QuestionPreviewCard:
for (final fig in question.figures)
  Padding(
    padding: const EdgeInsets.only(top: AppSpacing.md),
    child: _FigureSlot(
      locator: fig.locator,          // ← use fig.locator
      caption: fig.caption,
      bytes: figureBytes[fig.locator],
      onChanged: onFigureChanged,
    ),
  ),

          for (final part in question.parts)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: _PartView(
                qNum: question.number,
                part: part,
                figureBytes: figureBytes,
                onFigureChanged: onFigureChanged,
                onPartMarksChanged: (marks) =>
                    onPartMarksChanged(question.number, part.label, marks),
                onSubMarksChanged: (subLabel, marks) => onSubMarksChanged(
                    question.number, part.label, subLabel, marks),
              ),
            ),

          const SizedBox(height: AppSpacing.md),

          DropdownButtonFormField<String>(
            value: selectedTopicId,
            decoration: const InputDecoration(
              labelText: 'Topic',
              isDense: true,
            ),
            items: topics
                .map((t) => DropdownMenuItem(
                      value: t['id'] as String,
                      child: Text(t['name'] as String),
                    ))
                .toList(),
            onChanged: onTopicChanged,
          ),
        ],
      ),
    );
  }
}

class _PartView extends StatelessWidget {
  final int qNum;
  final PastPartDraft part;
  final Map<String, Uint8List> figureBytes;
  final void Function(String locator, Uint8List? bytes) onFigureChanged;
  final ValueChanged<int?> onPartMarksChanged;
  final void Function(String subLabel, int? marks) onSubMarksChanged;

  const _PartView({
    required this.qNum,
    required this.part,
    required this.figureBytes,
    required this.onFigureChanged,
    required this.onPartMarksChanged,
    required this.onSubMarksChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusChip),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('PART ${part.label}',
                  style: AppTextStyles.labelMd),
              const SizedBox(width: AppSpacing.sm),
              _EditableMarkBadge(
                marks: part.marks,
                onChanged: onPartMarksChanged,
              ),
            ],
          ),
          if (part.text.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(part.text, style: AppTextStyles.bodySm),
          ],

          // In _QuestionPreviewCard:
for (final fig in part.figures)
  Padding(
    padding: const EdgeInsets.only(top: AppSpacing.md),
    child: _FigureSlot(
      locator: fig.locator,          // ← use fig.locator
      caption: fig.caption,
      bytes: figureBytes[fig.locator],
      onChanged: onFigureChanged,
    ),
  ),

          for (final sub in part.subs)
  Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: _SubView(
      qNum: qNum,
      partLabel: part.label,
      sub: sub,
      partHasMarks: part.marks != null,   // ← new
      figureBytes: figureBytes,
      onFigureChanged: onFigureChanged,
      onSubMarksChanged: (marks) => onSubMarksChanged(sub.label, marks),
    ),
  ),
        ],
      ),
    );
  }
}

class _SubView extends StatelessWidget {
  final int qNum;
  final String partLabel;
  final PastSubDraft sub;
  final bool partHasMarks;   // ← new
  final Map<String, Uint8List> figureBytes;
  final void Function(String locator, Uint8List? bytes) onFigureChanged;
  final ValueChanged<int?> onSubMarksChanged;

  const _SubView({
    required this.qNum,
    required this.partLabel,
    required this.sub,
    required this.partHasMarks,
    required this.figureBytes,
    required this.onFigureChanged,
    required this.onSubMarksChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('(${sub.label})', style: AppTextStyles.labelSm),
              // Only show the sub mark when the part has no mark.
              if (!partHasMarks) ...[
                const SizedBox(width: 6),
                _EditableMarkBadge(
                  marks: sub.marks,
                  onChanged: onSubMarksChanged,
                  compact: true,
                ),
              ],
            ],
          ),
          if (sub.text.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(sub.text, style: AppTextStyles.bodySm),
          ],
          for (final fig in sub.figures)
  Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: _FigureSlot(
      locator: fig.locator,
      caption: fig.caption,
      bytes: figureBytes[fig.locator],
      onChanged: onFigureChanged,
    ),
  ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  const _Pill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Text(
        text,
        style: AppTextStyles.captionXs.copyWith(color: AppColors.primary),
      ),
    );
  }
}

class _FigureSlot extends StatelessWidget {
  final String locator;
  final String? caption;
  final Uint8List? bytes;
  final void Function(String locator, Uint8List? bytes) onChanged;

  const _FigureSlot({
    required this.locator,
    required this.caption,
    required this.bytes,
    required this.onChanged,
  });

  Future<void> _pick() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final b = await file.readAsBytes();
    onChanged(locator, b);
  }

  @override
  Widget build(BuildContext context) {
    if (bytes == null) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.image_outlined, size: 16),
              label: Text(
                caption == null
                    ? 'Attach figure'
                    : 'Attach figure ($caption)',
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (caption != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(caption!, style: AppTextStyles.captionXs),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusChip),
          child: Image.memory(bytes!, height: 140, fit: BoxFit.contain),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            TextButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.refresh_rounded, size: 14),
              label: const Text('Replace'),
            ),
            TextButton.icon(
              onPressed: () => onChanged(locator, null),
              icon: const Icon(Icons.close_rounded, size: 14),
              label: const Text('Remove'),
            ),
          ],
        ),
      ],
    );
  }
}

class _EditableMarkBadge extends StatelessWidget {
  final int? marks;
  final ValueChanged<int?> onChanged;
  final bool compact;

  const _EditableMarkBadge({
    required this.marks,
    required this.onChanged,
    this.compact = false,
  });

  Future<void> _edit(BuildContext context) async {
    final controller = TextEditingController(text: marks?.toString() ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Marks'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. 6',
            labelText: 'Marks for this part',
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('__CLEAR__'),
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null) return;   // cancelled

    if (result == '__CLEAR__') {
      onChanged(null);
      return;
    }

    final trimmed = result.trim();
    if (trimmed.isEmpty) {
      onChanged(null);
      return;
    }
    final parsed = int.tryParse(trimmed);
    if (parsed != null) onChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = marks == null;
    final label = isEmpty ? '[?]' : '[$marks]';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _edit(context),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 6 : 8,
            vertical: compact ? 1 : 2,
          ),
          decoration: BoxDecoration(
            color: isEmpty
                ? AppColors.warningBg
                : AppColors.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(AppSpacing.radiusChip),
            border: Border.all(
              color: isEmpty
                  ? AppColors.warningBorder
                  : AppColors.primary.withOpacity(0.15),
            ),
          ),
          child: Text(
            label,
            style: (compact
                    ? AppTextStyles.captionXs
                    : AppTextStyles.caption)
                .copyWith(
              fontWeight: FontWeight.w700,
              color: isEmpty ? AppColors.warning : AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}