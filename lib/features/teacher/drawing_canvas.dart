import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class DrawingCanvas extends StatefulWidget {
  final Function(String base64Image) onSave;

  const DrawingCanvas({super.key, required this.onSave});

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  final List<_DrawingStroke> _strokes = [];
  _DrawingStroke? _currentStroke;
  Color _currentColor = Colors.black;
  double _strokeWidth = 3.0;
  final GlobalKey _repaintKey = GlobalKey();

  // Custom color palette with more drawing-friendly colors
  final List<Color> _colorPalette = [
    Colors.black,
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.brown,
    Colors.teal,
    Colors.pink,
    Colors.indigo,
    Colors.amber.shade700,
    Colors.cyan,
    Colors.deepOrange,
    Colors.lightGreen,
    Colors.grey,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Draw Diagram'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: () {
              setState(() {
                if (_strokes.isNotEmpty) _strokes.removeLast();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () => _captureAndSave(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.grey.shade100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Scrollable color palette
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _colorPalette.map((color) {
                      final isSelected = _currentColor.value == color.value;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setState(() => _currentColor = color),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: isSelected
                                  ? Border.all(
                                      color: color == Colors.black
                                          ? Colors.white
                                          : Colors.black,
                                      width: 2.5,
                                    )
                                  : Border.all(
                                      color: Colors.grey.shade400,
                                      width: 0.5,
                                    ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: color.withOpacity(0.4),
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      )
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
                // Stroke width slider
                Row(
                  children: [
                    const Icon(Icons.circle, size: 12, color: Colors.grey),
                    Expanded(
                      child: Slider(
                        value: _strokeWidth,
                        min: 1,
                        max: 12,
                        activeColor: const Color(0xFF1A237E),
                        onChanged: (v) => setState(() => _strokeWidth = v),
                      ),
                    ),
                    const Icon(Icons.circle, size: 24, color: Colors.grey),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        '${_strokeWidth.toInt()}px',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Drawing area
          Expanded(
            child: RepaintBoundary(
              key: _repaintKey,
              child: Container(
                color: Colors.white,
                child: GestureDetector(
                  onPanStart: (details) {
                    setState(() {
                      _currentStroke = _DrawingStroke(
                        color: _currentColor,
                        strokeWidth: _strokeWidth,
                        points: [details.localPosition],
                      );
                      _strokes.add(_currentStroke!);
                    });
                  },
                  onPanUpdate: (details) {
                    setState(() {
                      _currentStroke?.points.add(details.localPosition);
                    });
                  },
                  onPanEnd: (details) {
                    setState(() {
                      _currentStroke = null;
                    });
                  },
                  child: CustomPaint(
                    painter: _DrawingPainter(strokes: _strokes),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _captureAndSave() async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // Capture the drawing area as an image
      final boundary =
          _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;

      if (boundary == null) {
        Navigator.pop(context); // Dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error capturing drawing')),
        );
        return;
      }

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        Navigator.pop(context); // Dismiss loading
        return;
      }

      final pngBytes = byteData.buffer.asUint8List();
      final base64Image = base64Encode(pngBytes);

      Navigator.pop(context); // Dismiss loading

      // Call the onSave callback with the base64 image
      widget.onSave(base64Image);
    } catch (e) {
      Navigator.pop(context); // Dismiss loading if showing
      print('Error capturing drawing: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}

class _DrawingStroke {
  final Color color;
  final double strokeWidth;
  final List<Offset> points;

  _DrawingStroke({
    required this.color,
    required this.strokeWidth,
    required this.points,
  });
}

class _DrawingPainter extends CustomPainter {
  final List<_DrawingStroke> strokes;

  _DrawingPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;

      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.strokeWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final path = Path();
      path.moveTo(stroke.points.first.dx, stroke.points.first.dy);

      for (int i = 1; i < stroke.points.length; i++) {
        path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}