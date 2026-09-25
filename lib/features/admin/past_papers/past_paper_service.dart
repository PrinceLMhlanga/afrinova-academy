import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'past_paper_parser.dart';

/// Writes a parsed past paper to Supabase.
///
/// Figures are uploaded at save time. The caller supplies a map from
/// **figure locator** to bytes, where the locator identifies exactly
/// which figure slot the bytes belong to:
///
///   "q1.stem.0"        first figure in question 1's stem
///   "q1.part.a.0"      first figure in question 1, part a
///   "q1.part.c.sub.ii.0"  first figure in question 1, part c, sub-part ii
///
/// Only slots that have bytes attached will upload. Slots the admin
/// left empty are stored with `url: null` so the tree structure is
/// preserved for later editing.
class PastPaperService {
  PastPaperService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Build the locator for a figure at a given position.
  static String locatorStem(int qNum, int i) => 'q$qNum.stem.$i';

  static String locatorPart(int qNum, String partLabel, int i) =>
      'q$qNum.part.$partLabel.$i';

  static String locatorSub(
    int qNum,
    String partLabel,
    String subLabel,
    int i,
  ) =>
      'q$qNum.part.$partLabel.sub.$subLabel.$i';

  Future<String> savePaper({
  required PastPaperDraft paper,

  // Resolved metadata
  required String subjectId,
  required String levelId,
  required String title,
  required String paperType,
  required int year,
  required String session,
  required String source,
  required int durationMinutes,
  String? instructions,

  // question number → topic id
  required Map<int, String> topicByQuestion,

  // figure locator → bytes
  Map<String, Uint8List> figureBytes = const {},

  // Original DeepSeek text, for audit
  String? rawTranscript,

  bool publish = false,
}) async {
  final userId = _client.auth.currentUser?.id;

  // ── 1. Create the paper FIRST ──
  // We create the paper before uploading figures so every figure can
  // be stored under `<paper_id>/...`, which guarantees uniqueness
  // across papers (two papers can't have the same paper_id).
  final paperInsert = await _client
      .from('past_papers')
      .insert({
        'title': title,
        'subject_id': subjectId,
        'level_id': levelId,
        'paper_type': paperType,
        'year': year,
        'session': session,
        'source': source,
        'duration_minutes': durationMinutes,
        'instructions': instructions,
        'section_notes': paper.sectionNotes,
        'raw_transcript': rawTranscript,
        'is_published': publish,
        'created_by': userId,
      })
      .select('id')
      .single();

  final paperId = paperInsert['id'] as String;

  // ── 2. Upload figures, scoped to the paper ──
  // Storage path = `<paper_id>/<locator_with_underscores>.png`.
  // The DB will store this full path, not just the filename, so
  // readers can resolve figures without ambiguity.
  final uploadedUrls = <String, String>{}; // locator → full storage path
  for (final entry in figureBytes.entries) {
    final locator = entry.key;
    final bytes = entry.value;
    if (bytes.isEmpty) continue;

    final safeLocator = locator.replaceAll('.', '_');
    final path = '$paperId/$safeLocator.png';

    try {
      await _client.storage.from('past-paper-figures').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/png',
              upsert: true,
            ),
          );
      uploadedUrls[locator] = path;
    } catch (e) {
      debugPrint('[PastPaperService] upload failed for $locator: $e');
    }
  }

  // ── 3. Insert questions with figure URLs ──
  for (final q in paper.questions) {
    final topicId = topicByQuestion[q.number];

    // 3a. Stem figures — keyed by each figure's own locator
    final stemFigures = q.figures.map((fig) {
      return {
        'url': uploadedUrls[fig.locator],
        'caption': fig.caption,
        'alt': null,
      };
    }).toList();

    // 3b. Parts (recursive) — also keyed by each figure's own locator
    final partsJson = _serializeParts(q.parts, uploadedUrls);

    await _client.from('past_questions').insert({
      'paper_id': paperId,
      'question_number': q.number,
      'display_order': q.number,
      'stem': q.stem,
      'marks': q.marks,
      'parts': partsJson,
      'figures': stemFigures,
      'topic_id': topicId,
      'section': q.section,
    });
  }

  return paperId;
}

 List<Map<String, dynamic>> _serializeParts(
  List<PastPartDraft> parts,
  Map<String, String> uploadedUrls,
) {
  return parts.map((p) {
    // Part figures — each figure's own locator is the key.
    final partFigures = p.figures.map((fig) {
      return {
        'url': uploadedUrls[fig.locator],
        'caption': fig.caption,
        'alt': null,
      };
    }).toList();

    // Sub-parts (recursive one level only — no deeper nesting in the
    // data model).
    final subJson = p.subs.map((s) {
      final subFigures = s.figures.map((fig) {
        return {
          'url': uploadedUrls[fig.locator],
          'caption': fig.caption,
          'alt': null,
        };
      }).toList();

      return {
        'label': s.label,
        'marks': s.marks,
        'text': s.text,
        'figures': subFigures,
      };
    }).toList();

    return {
      'label': p.label,
      'marks': p.marks,
      'text': p.text,
      'figures': partFigures,
      'subparts': subJson,
    };
  }).toList();
}
  /// Fetch topics for a given subject + level, ordered for display.
  Future<List<Map<String, dynamic>>> getTopicsFor({
    required String subjectId,
    required String levelId,
  }) async {
    final res = await _client
        .from('topics')
        .select('id, name, display_order')
        .eq('subject_id', subjectId)
        .eq('level_id', levelId)
        .order('display_order', ascending: true);

    return (res as List)
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  /// Fetch all subjects for the metadata dropdown.
  Future<List<Map<String, dynamic>>> getSubjects() async {
    final res = await _client
        .from('subjects')
        .select('id, name')
        .eq('is_active', true)
        .order('name');
    return (res as List)
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  /// Fetch all levels for the metadata dropdown.
  Future<List<Map<String, dynamic>>> getLevels() async {
    final res = await _client
        .from('levels')
        .select('id, name, display_order')
        .order('display_order');
    return (res as List)
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }
}