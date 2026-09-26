
class PastPaperParser {
  PastPaperParser();

  PastPaperParseResult parse(String input) {
    final lines = input.split(RegExp(r'\r?\n'));
    final paper = _WorkingPaper();
    _WorkingQuestion? currentQ;
    _WorkingPart? currentPart;
    _WorkingSub? currentSub;

    // Where to accumulate content right now. One of:
    //   'instructions' | 'section_note' | 'stem' | 'part' | 'sub' | null
    String? contentTarget;

    final errors = <String>[];

    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final line = raw.trimRight();
      final trimmed = line.trim();

      // ── Blank line: preserve paragraph break ──
      if (trimmed.isEmpty) {
        _appendLine(
          paper, currentQ, currentPart, currentSub, contentTarget, '',
        );
        continue;
      }

      // ── Metadata (only before first question) ──
      if (currentQ == null) {
        final metaMatch = RegExp(
          r'^(PAPER|SUBJECT|LEVEL|TYPE|YEAR|SESSION|SOURCE|DURATION):\s*(.*)$',
          caseSensitive: false,
        ).firstMatch(trimmed);
        if (metaMatch != null) {
          final key = metaMatch.group(1)!.toUpperCase();
          final value = metaMatch.group(2)!.trim();
          // Ignore empty metadata values.
          if (value.isNotEmpty) {
            _assignMetadata(paper, key, value);
          }
          contentTarget = null;
          continue;
        }

        if (trimmed.toUpperCase() == 'INSTRUCTIONS:') {
          contentTarget = 'instructions';
          continue;
        }
      }

      // ── SECTION marker ──
      final sectionMatch =
          RegExp(r'^SECTION:\s*(.+)$', caseSensitive: false)
              .firstMatch(trimmed);
      if (sectionMatch != null) {
        final name = sectionMatch.group(1)!.trim();
        if (name.isNotEmpty) {
          paper.currentSection = name;
        }
        contentTarget = null;
        continue;
      }

      // ── SECTION_NOTE marker ──
      final sectionNoteMatch =
          RegExp(r'^SECTION_NOTE:\s*(.*)$', caseSensitive: false)
              .firstMatch(trimmed);
      if (sectionNoteMatch != null) {
        final note = sectionNoteMatch.group(1)!.trim();
        final sec = paper.currentSection;
        if (sec != null && note.isNotEmpty) {
          paper.sectionNotes[sec] = note;
          contentTarget = 'section_note';
        } else {
          contentTarget = null;
        }
        continue;
      }

      // ── Question header ──
      // Accepts:
      //   Q1
      //   Q1 [15]
      //   Q1 [15] [TOPIC: 3]
      //   Q1 [15] [Oscillations]
      //   Q1 [15] [TOPIC: Oscillations]
      //   Q1 [Oscillations]
      //
      // Group 1 = number
      // Group 2 = marks (optional)
      // Group 3 = topic content, number or name (optional)
      final qMatch = RegExp(
        r'^Q(\d+)\s*(?:\[(\d+)\])?\s*(?:\[\s*(?:TOPIC:\s*)?([^\]]+?)\s*\])?\s*$',
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (qMatch != null) {
        final number = int.tryParse(qMatch.group(1)!) ?? 0;
        final marks =
            qMatch.group(2) != null ? int.tryParse(qMatch.group(2)!) : null;

        int? topicIndex;
        String? topicName;
        final topicRaw = qMatch.group(3)?.trim();
        if (topicRaw != null && topicRaw.isNotEmpty) {
          final asInt = int.tryParse(topicRaw);
          if (asInt != null) {
            topicIndex = asInt;
          } else {
            topicName = topicRaw;
          }
        }

        currentQ = _WorkingQuestion(
          number: number,
          marks: marks,
          topicIndex: topicIndex,
          topicName: topicName,
          section: paper.currentSection,
        );
        paper.questions.add(currentQ);
        currentPart = null;
        currentSub = null;
        contentTarget = 'stem';
        continue;
      }

      // ── PART header: "PART a [6]" (marks optional) ──
      final partMatch =
    RegExp(r'^PART\s+([a-z])\s*(?:\[(\d+)\])?\s*(?:\[\s*(?:TOPIC:\s*)?([^\]]+?)\s*\])?\s*$',
            caseSensitive: false)
        .firstMatch(trimmed);
if (partMatch != null) {
  if (currentQ == null) {
    errors.add('Line ${i + 1}: PART before any Q — ignored.');
    continue;
  }
  final label = partMatch.group(1)!.toLowerCase();
  final marks =
      partMatch.group(2) != null ? int.tryParse(partMatch.group(2)!) : null;

  // Topic on the PART line — either a number or a name.
  int? topicIndex;
  String? topicName;
  final topicRaw = partMatch.group(3)?.trim();
  if (topicRaw != null && topicRaw.isNotEmpty) {
    final asInt = int.tryParse(topicRaw);
    if (asInt != null) {
      topicIndex = asInt;
    } else {
      topicName = topicRaw;
    }
  }

  currentPart = _WorkingPart(
    label: label,
    marks: marks,
    topicIndex: topicIndex,
    topicName: topicName,
  );
  currentQ.parts.add(currentPart);
  currentSub = null;
  contentTarget = 'part';
  continue;
}
      // ── SUB header: "SUB i [2]" (marks optional) ──
      final subMatch =
          RegExp(r'^SUB\s+([ivxl]+)\s*(?:\[(\d+)\])?\s*$',
                  caseSensitive: false)
              .firstMatch(trimmed);
      if (subMatch != null) {
        if (currentPart == null) {
          errors.add('Line ${i + 1}: SUB before any PART — ignored.');
          continue;
        }
        final label = subMatch.group(1)!.toLowerCase();
        final marks =
            subMatch.group(2) != null ? int.tryParse(subMatch.group(2)!) : null;
        currentSub = _WorkingSub(label: label, marks: marks);
        currentPart.subs.add(currentSub);
        contentTarget = 'sub';
        continue;
      }

// ── Figure marker: "[See diagram]" or "[See diagram: Fig 1.1]" ──
// The leading word is broadened to tolerate DeepSeek emitting
// "table", "graph", "figure", etc. We only use the caption.
final diagramMatch = RegExp(
  r'^\[See\s+(?:diagram|figure|fig|table|graph|chart|image|photo)(?::\s*(.+?))?\]$',
  caseSensitive: false,
).firstMatch(trimmed);

if (diagramMatch != null) {
  final caption = diagramMatch.group(1)?.trim();

  if (contentTarget == 'sub' &&
      currentSub != null &&
      currentQ != null &&
      currentPart != null) {
    final idx = currentSub.figures.length;
    final locator =
        'q${currentQ.number}.part.${currentPart.label}.sub.${currentSub.label}.$idx';
    currentSub.figures.add(
      _WorkingFigure(caption: caption, locator: locator),
    );
    // Insert a marker into the text at this exact position.
    _appendLine(paper, currentQ, currentPart, currentSub, 'sub',
        '{{fig:$idx}}');
  } else if (contentTarget == 'part' &&
      currentPart != null &&
      currentQ != null) {
    final idx = currentPart.figures.length;
    final locator =
        'q${currentQ.number}.part.${currentPart.label}.$idx';
    currentPart.figures.add(
      _WorkingFigure(caption: caption, locator: locator),
    );
    _appendLine(paper, currentQ, currentPart, currentSub, 'part',
        '{{fig:$idx}}');
  } else if (contentTarget == 'stem' && currentQ != null) {
    final idx = currentQ.figures.length;
    final locator = 'q${currentQ.number}.stem.$idx';
    currentQ.figures.add(
      _WorkingFigure(caption: caption, locator: locator),
    );
    _appendLine(paper, currentQ, currentPart, currentSub, 'stem',
        '{{fig:$idx}}');
  }
  continue;
}

      // ── Anything else: content for the current context ──
      if (contentTarget == null) {
        continue;
      }
      _appendLine(
        paper, currentQ, currentPart, currentSub, contentTarget, line,
      );
    }

    // ── Post-process ──
    for (final q in paper.questions) {
      q.stem = StringBuffer(q.stem.toString().trim());
      for (final p in q.parts) {
        p.text = StringBuffer(p.text.toString().trim());
        for (final s in p.subs) {
          s.text = StringBuffer(s.text.toString().trim());
        }
      }

      // Propagate question-level topic to parts that don't have one.
for (final q in paper.questions) {
  if (q.topicIndex == null && q.topicName == null) continue;
  for (final p in q.parts) {
    if (p.topicIndex != null || p.topicName != null) continue;
    p.topicIndex = q.topicIndex;
    p.topicName = q.topicName;
  }
}

      // Duplicated part-text rescue: if a part's own text just repeats
      // its first sub-part's text, drop it. This happens when DeepSeek
      // writes the intro sentence both under PART and under SUB i.
      for (final p in q.parts) {
        if (p.text.isNotEmpty && p.subs.isNotEmpty) {
          final partText = p.text.toString().trim();
          final firstSubText = p.subs.first.text.toString().trim();
          // Strip any leading "(i)" / "i." / "i)" prefix before comparing.
          final normalised =
              partText.replaceFirst(RegExp(r'^\(?[ivxl]+\)?\.?\s+'), '');
          if (normalised == firstSubText) {
            p.text = StringBuffer();
          }
        }
      }

      // Marks rescue: if a part has no mark, but exactly one sub-part
      // has a mark and it's the last sub, lift it to the part. Handles
      // the ZIMSEC physics/chem pattern where the total is printed next
      // to the last sub-part.
      for (final p in q.parts) {
        if (p.marks != null) continue;
        if (p.subs.isEmpty) continue;
        final markedSubs = p.subs.where((s) => s.marks != null).toList();
        if (markedSubs.length != 1) continue;
        final lastSub = p.subs.last;
        if (lastSub.marks == null) continue;
        p.marks = lastSub.marks;
        lastSub.marks = null;
      }

      // Compute question marks if not stated on the Q line.
      if (q.marks == null && q.parts.isNotEmpty) {
        final partMarks = q.parts
            .where((p) => p.marks != null)
            .fold<int>(0, (a, b) => a + (b.marks ?? 0));
        if (partMarks > 0) {
          q.marks = partMarks;
        } else {
          final subMarks = q.parts
              .expand((p) => p.subs)
              .where((s) => s.marks != null)
              .fold<int>(0, (a, b) => a + (b.marks ?? 0));
          if (subMarks > 0) q.marks = subMarks;
        }
      }
    }

    return PastPaperParseResult(
      paper: paper.toImmutable(),
      errors: errors,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Internals
  // ─────────────────────────────────────────────────────────────

  void _assignMetadata(_WorkingPaper paper, String key, String value) {
    switch (key) {
      case 'PAPER':
        paper.title = value;
        break;
      case 'SUBJECT':
        paper.subjectName = value;
        break;
      case 'LEVEL':
        paper.levelName = value;
        break;
      case 'TYPE':
        paper.paperType = value;
        break;
      case 'YEAR':
        paper.year = int.tryParse(value);
        break;
      case 'SESSION':
        paper.session = value;
        break;
      case 'SOURCE':
        paper.source = value;
        break;
      case 'DURATION':
        paper.durationMinutes = int.tryParse(value);
        break;
    }
  }

  void _appendLine(
    _WorkingPaper paper,
    _WorkingQuestion? q,
    _WorkingPart? part,
    _WorkingSub? sub,
    String? target,
    String line,
  ) {
    if (target == null) return;

    void appendTo(StringBuffer b) {
      if (b.isNotEmpty) b.write('\n');
      b.write(line);
    }

    switch (target) {
      case 'instructions':
        appendTo(paper.instructions);
        break;
      case 'section_note':
        final sec = paper.currentSection;
        if (sec != null) {
          final existing = paper.sectionNotes[sec];
          if (existing == null || existing.isEmpty) {
            paper.sectionNotes[sec] = line;
          } else {
            paper.sectionNotes[sec] = '$existing\n$line';
          }
        }
        break;
      case 'stem':
        if (q != null) appendTo(q.stem);
        break;
      case 'part':
        if (part != null) appendTo(part.text);
        break;
      case 'sub':
        if (sub != null) appendTo(sub.text);
        break;
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Immutable output model
// ─────────────────────────────────────────────────────────────

class PastPaperParseResult {
  final PastPaperDraft paper;
  final List<String> errors;

  const PastPaperParseResult({required this.paper, required this.errors});

  bool get hasErrors => errors.isNotEmpty;
  int get questionCount => paper.questions.length;
}

class PastPaperDraft {
  final String? title;
  final String? subjectName;
  final String? levelName;
  final String? paperType;
  final int? year;
  final String? session;
  final String? source;
  final int? durationMinutes;
  final String? instructions;
  final Map<String, String> sectionNotes;
  final List<PastQuestionDraft> questions;

  const PastPaperDraft({
    this.title,
    this.subjectName,
    this.levelName,
    this.paperType,
    this.year,
    this.session,
    this.source,
    this.durationMinutes,
    this.instructions,
    this.sectionNotes = const {},
    required this.questions,
  });
}

class PastQuestionDraft {
  int number;
  int? marks;
  int? topicIndex;
  String? topicName;
  String? section;
  String stem;
  List<PastFigureDraft> figures;
  List<PastPartDraft> parts;

  PastQuestionDraft({
    required this.number,
    this.marks,
    this.topicIndex,
    this.topicName,
    this.section,
    required this.stem,
    required this.figures,
    required this.parts,
  });
}

class PastPartDraft {
  String label;
  int? marks;
  String text;
  List<PastFigureDraft> figures;
  List<PastSubDraft> subs;

  // NEW — topic for this part, resolved against the admin's topic
  // list. Null if not set.
  int? topicIndex;         // 1-based index from DeepSeek's [TOPIC: n]
  String? topicName;       // or the name from [Topic Name]

  PastPartDraft({
    required this.label,
    this.marks,
    required this.text,
    required this.figures,
    required this.subs,
    this.topicIndex,
    this.topicName,
  });
}

class PastSubDraft {
  String label;
  int? marks;
  String text;
  List<PastFigureDraft> figures;

  PastSubDraft({
    required this.label,
    this.marks,
    required this.text,
    required this.figures,
  });
}




class PastFigureDraft {
  final String? caption;
  /// Unique locator for this figure, built when the figure is parsed.
  /// Format: "q1.stem.0", "q1.part.a.0", "q1.part.c.sub.ii.1", etc.
  /// Used to match attached bytes to the correct slot in the tree.
  final String locator;

  const PastFigureDraft({
    this.caption,
    required this.locator,
  });
}

// ─────────────────────────────────────────────────────────────
// Mutable working models (used during parsing only)
// ─────────────────────────────────────────────────────────────

class _WorkingFigure {
  final String? caption;
  final String locator;

  _WorkingFigure({this.caption, required this.locator});

  PastFigureDraft toImmutable() =>
      PastFigureDraft(caption: caption, locator: locator);
}

class _WorkingPaper {
  String? title;
  String? subjectName;
  String? levelName;
  String? paperType;
  int? year;
  String? session;
  String? source;
  int? durationMinutes;
  final StringBuffer instructions = StringBuffer();
  final List<_WorkingQuestion> questions = [];
  String? currentSection;
  final Map<String, String> sectionNotes = {};

  PastPaperDraft toImmutable() {
    return PastPaperDraft(
      title: title,
      subjectName: subjectName,
      levelName: levelName,
      paperType: paperType,
      year: year,
      session: session,
      source: source,
      durationMinutes: durationMinutes,
      instructions: instructions.isEmpty ? null : instructions.toString(),
      sectionNotes: Map<String, String>.from(sectionNotes),
      questions: questions.map((q) => q.toImmutable()).toList(),
    );
  }
}

class _WorkingQuestion {
  final int number;
  int? marks;
  final int? topicIndex;
  final String? topicName;
  final String? section;
  StringBuffer stem = StringBuffer();
  final List<_WorkingFigure> figures = [];
  final List<_WorkingPart> parts = [];

  _WorkingQuestion({
    required this.number,
    this.marks,
    this.topicIndex,
    this.topicName,
    this.section,
  });

  PastQuestionDraft toImmutable() => PastQuestionDraft(
        number: number,
        marks: marks,
        topicIndex: topicIndex,
        topicName: topicName,
        section: section,
        stem: stem.toString(),
        figures: figures.map((f) => f.toImmutable()).toList(),
        parts: parts.map((p) => p.toImmutable()).toList(),
      );
}

class _WorkingPart {
  final String label;
  int? marks;
  StringBuffer text = StringBuffer();
  final List<_WorkingFigure> figures = [];
  final List<_WorkingSub> subs = [];
  int? topicIndex;
  String? topicName;

  _WorkingPart({
    required this.label,
    this.marks,
    this.topicIndex,
    this.topicName,
  });

 PastPartDraft toImmutable() => PastPartDraft(
      label: label,
      marks: marks,
      text: text.toString(),
      figures: figures.map((f) => f.toImmutable()).toList(),
      subs: subs.map((s) => s.toImmutable()).toList(),
      topicIndex: topicIndex,
      topicName: topicName,
    );
}

class _WorkingSub {
  final String label;
  int? marks;
  StringBuffer text = StringBuffer();
  final List<_WorkingFigure> figures = [];

  _WorkingSub({required this.label, this.marks});

  PastSubDraft toImmutable() => PastSubDraft(
        label: label,
        marks: marks,
        text: text.toString(),
        figures: figures.map((f) => f.toImmutable()).toList(),
      );
}

class PastPaperParseException implements Exception {
  final String message;
  PastPaperParseException(this.message);
  @override
  String toString() => 'PastPaperParseException: $message';
}