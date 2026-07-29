import 'dart:async';

class ChatStreamController {
  final StreamController<String> _textStreamController = StreamController<String>.broadcast();
  final StringBuffer _textBuffer = StringBuffer();

  Stream<String> get textStream => _textStreamController.stream;
  String get fullText => _textBuffer.toString();

  void addChunk(String newChunk) {
    _textBuffer.write(newChunk);
    _textStreamController.add(_textBuffer.toString());
  }

  void closeStream() {
    if (!_textStreamController.isClosed) {
      _textStreamController.close();
    }
  }
}
