import 'dart:async';

class ChatStreamController {
  final StreamController<String> _textStreamController = StreamController<String>.broadcast();
  String _fullText = '';

  Stream<String> get textStream => _textStreamController.stream;
  String get fullText => _fullText;

  void addChunk(String fullTextSoFar) {  // ✅ Receives complete text so far
    _fullText = fullTextSoFar;
    _textStreamController.add(_fullText);
  }

  void closeStream() {
    _textStreamController.close();
  }
}