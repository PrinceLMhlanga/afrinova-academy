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

    // ── 1. Upload all figures first, collect url map ──
    // We do this before inserting the paper so every node's jsonb
    // already carries its figure urls.
    final uploadedUrls = <String, String>{}; // locator → storage path
    for (final entry in figureBytes.entries) {
      final locator = entry.key;
      final bytes = entry.value;
      if (bytes.isEmpty) continue;

      // Sanitize locator for use in a storage path.
      final safeLocator = locator.replaceAll('.', '_');
      final path = 'pending/$safeLocator.png';

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

    // ── 2. Create the paper ──
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

    // ── 3. Insert questions ──
    for (final q in paper.questions) {
      final topicId = topicByQuestion[q.number];

      // 3a. Serialize the question's own figures
      final stemFigures = <Map<String, dynamic>>[];
      for (var i = 0; i < q.figures.length; i++) {
        final loc = locatorStem(q.number, i);
        stemFigures.add({
          'url': uploadedUrls[loc],
          'caption': q.figures[i].caption,
          'alt': null,
        });
      }

      // 3b. Serialize parts (recursively, with figure urls)
      final partsJson = _serializeParts(q.number, q.parts, uploadedUrls);

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

    // ── 4. Move uploaded files into their final paper folder ──
    // Not implemented here. Storage paths are fine under `pending/`
    // for now; a nightly job or admin action can organize later.
    // If you want immediate reorganization, loop and use the storage
    // move API — skipping for simplicity.

    return paperId;
  }

  List<Map<String, dynamic>> _serializeParts(
    int qNum,
    List<PastPartDraft> parts,
    Map<String, String> uploadedUrls,
  ) {
    return parts.map((p) {
      // Part figures
      final partFigures = <Map<String, dynamic>>[];
      for (var i = 0; i < p.figures.length; i++) {
        final loc = locatorPart(qNum, p.label, i);
        partFigures.add({
          'url': uploadedUrls[loc],
          'caption': p.figures[i].caption,
          'alt': null,
        });
      }

      // Sub-parts
      final subJson = p.subs.map((s) {
        final subFigures = <Map<String, dynamic>>[];
        for (var i = 0; i < s.figures.length; i++) {
          final loc = locatorSub(qNum, p.label, s.label, i);
          subFigures.add({
            'url': uploadedUrls[loc],
            'caption': s.figures[i].caption,
            'alt': null,
          });
        }

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