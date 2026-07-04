import 'dart:convert';

class TableMarkup {
  static String encodeTableMarker(List<List<String>> cells) {
    final payload = jsonEncode(cells);
    final encoded = base64Encode(utf8.encode(payload));
    return '%%TABLE:$encoded%%';
  }

  static List<List<String>>? decodeTableMarker(String? marker) {
    if (marker == null || marker.isEmpty) return null;

    final match = RegExp(r'%%TABLE:([A-Za-z0-9+/=]+)%%').firstMatch(marker);
    if (match == null) return null;

    try {
      final decoded = utf8.decode(base64Decode(match.group(1)!));
      final parsed = jsonDecode(decoded);
      if (parsed is List) {
        return parsed
            .map<List<String>>((row) => (row as List).map((cell) => cell.toString()).toList())
            .toList();
      }
    } catch (_) {}

    return null;
  }

  static String? extractTableMarker(String text) {
    final match = RegExp(r'%%TABLE:[A-Za-z0-9+/=]+%%').firstMatch(text);
    return match?.group(0);
  }

  static List<List<List<String>>> extractTables(String text) {
    final markers = RegExp(r'%%TABLE:[A-Za-z0-9+/=]+%%').allMatches(text);
    return markers
        .map((match) => decodeTableMarker(match.group(0)))
        .whereType<List<List<String>>>()
        .toList();
  }
}
