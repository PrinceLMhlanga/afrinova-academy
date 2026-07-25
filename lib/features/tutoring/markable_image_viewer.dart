import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class MarkableImageViewer extends StatefulWidget {
  final String imageUrl;
  final String? fileName;

  const MarkableImageViewer({
    super.key,
    required this.imageUrl,
    this.fileName,
  });

  @override
  State<MarkableImageViewer> createState() => _MarkableImageViewerState();
}

class _MarkableImageViewerState extends State<MarkableImageViewer> {
  final List<_DrawingStroke> _strokes = [];
  _DrawingStroke? _currentStroke;
  Color _selectedColor = Colors.red;
  double _strokeWidth = 4.0;
  bool _isEraser = false;
  ui.Image? _image;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final response = await http.get(Uri.parse(widget.imageUrl));
      final bytes = response.bodyBytes;
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _image = frame.image;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Load image error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _undo() {
    if (_strokes.isNotEmpty) {
      setState(() => _strokes.removeLast());
    }
  }

  void _clearAll() {
    setState(() => _strokes.clear());
  }

  Future<Uint8List> _exportMarkedImage() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    if (_image != null) {
      canvas.drawImage(_image!, Offset.zero, Paint());
    }
    
    for (final stroke in _strokes) {
      _drawStroke(canvas, stroke);
    }
    
    final picture = recorder.endRecording();
    final img = await picture.toImage(
      _image?.width ?? 1080,
      _image?.height ?? 1080,
    );
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  void _drawStroke(Canvas canvas, _DrawingStroke stroke) {
    if (stroke.points.isEmpty) return;
    final paint = Paint()
      ..color = stroke.isEraser ? Colors.white : stroke.color
      ..strokeWidth = stroke.isEraser ? 24 : stroke.width
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
    for (int i = 1; i < stroke.points.length; i++) {
      path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  Future<void> _sendMarkedImage() async {
    final markedBytes = await _exportMarkedImage();
    if (mounted) {
      // Return the marked image bytes
      Navigator.pop(context, {
        'bytes': markedBytes,
        'fileName': 'marked_${widget.fileName ?? 'image'}.png',
      });
    }
  }

 @override
Widget build(BuildContext context) {
  if (_isLoading || _image == null) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, elevation: 0),
      body: const Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }

  return Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      elevation: 0,
      title: const Text('Mark & Send'),
      actions: [
        IconButton(icon: const Icon(Icons.undo), onPressed: _undo, tooltip: 'Undo'),
        IconButton(icon: const Icon(Icons.layers_clear), onPressed: _clearAll, tooltip: 'Clear All'),
        IconButton(
          icon: const Icon(Icons.send_rounded, color: Color(0xFF25D366)),
          onPressed: _strokes.isEmpty ? null : _sendMarkedImage,
          tooltip: 'Send Marked Image',
        ),
      ],
    ),
    body: Column(
      children: [
        // Canvas with drawing overlay ON TOP
        Expanded(
          child: Stack(
            children: [
              // ✅ Base image with zoom/pan
              InteractiveViewer(
                child: RawImage(image: _image!, fit: BoxFit.contain),
              ),
              // ✅ Drawing layer ON TOP of InteractiveViewer
              Positioned.fill(
                child: GestureDetector(
                  onPanStart: (d) => setState(() {
                    _currentStroke = _DrawingStroke(
                      points: [d.localPosition],
                      color: _isEraser ? Colors.white : _selectedColor,
                      width: _strokeWidth,
                      isEraser: _isEraser,
                    );
                  }),
                  onPanUpdate: (d) => setState(() {
                    _currentStroke?.points.add(d.localPosition);
                  }),
                  onPanEnd: (d) {
                    if (_currentStroke != null && _currentStroke!.points.isNotEmpty) {
                      _strokes.add(_currentStroke!);
                      _currentStroke = null;
                    }
                  },
                  child: CustomPaint(
                    painter: _DrawingPainter(
                      strokes: _strokes,
                      currentStroke: _currentStroke,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Colors.grey.shade900,
          child: SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _colorDot(Colors.red, 'Red'),
                _colorDot(Colors.green, 'Green'),
                _colorDot(Colors.blue, 'Blue'),
                _colorDot(Colors.yellow, 'Yellow'),
                _colorDot(Colors.white, 'White'),
                _colorDot(Colors.black, 'Black'),
                const SizedBox(width: 12),
                _toolButton(Icons.cleaning_services, 'Eraser', true),
                _toolButton(Icons.undo, 'Undo', false),
                _toolButton(Icons.delete_outline, 'Clear', false),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

  Widget _colorDot(Color color, String tooltip) {
    final isSelected = _selectedColor == color && !_isEraser;
    return GestureDetector(
      onTap: () => setState(() { _selectedColor = color; _isEraser = false; }),
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 28, height: 28,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? Colors.white : Colors.transparent, width: 3,
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolButton(IconData icon, String tooltip, bool isEraser) {
    return GestureDetector(
      onTap: isEraser 
          ? () => setState(() => _isEraser = !_isEraser)
          : icon == Icons.undo 
              ? _undo 
              : _clearAll,
      child: Tooltip(
        message: tooltip,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isEraser 
                ? (_isEraser ? Colors.white.withOpacity(0.2) : Colors.transparent)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _DrawingStroke {
  final List<Offset> points;
  final Color color;
  final double width;
  final bool isEraser;
  _DrawingStroke({required this.points, required this.color, required this.width, this.isEraser = false});
}

class _DrawingPainter extends CustomPainter {
  final List<_DrawingStroke> strokes;
  final _DrawingStroke? currentStroke;
  _DrawingPainter({required this.strokes, this.currentStroke});

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }
    if (currentStroke != null) _drawStroke(canvas, currentStroke!);
  }

  void _drawStroke(Canvas canvas, _DrawingStroke stroke) {
    if (stroke.points.isEmpty) return;
    final paint = Paint()
      ..color = stroke.isEraser ? Colors.white : stroke.color
      ..strokeWidth = stroke.isEraser ? 24 : stroke.width
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
    for (int i = 1; i < stroke.points.length; i++) {
      path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter old) => true;
}