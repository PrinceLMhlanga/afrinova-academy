import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

class WhiteboardCanvas extends StatefulWidget {
  final Room room;
  final bool isTeacher;
  final String userName;

  const WhiteboardCanvas({
    super.key,
    required this.room,
    required this.isTeacher,
    required this.userName,
  });

  @override
  State<WhiteboardCanvas> createState() => _WhiteboardCanvasState();
}

class _WhiteboardCanvasState extends State<WhiteboardCanvas> {
  final List<_Stroke> _strokes = [];
  _Stroke? _currentStroke;
  
  Color _selectedColor = Colors.black;
  double _strokeWidth = 3.0;
  bool _isEraser = false;
  bool _showToolbar = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Toolbar
          if (widget.isTeacher && _showToolbar)
            _buildSimpleToolbar(),
          
          // Canvas
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onPanStart: widget.isTeacher ? _onPanStart : null,
                  onPanUpdate: widget.isTeacher ? _onPanUpdate : null,
                  onPanEnd: widget.isTeacher ? _onPanEnd : null,
                  child: Container(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    color: Colors.white,
                    child: CustomPaint(
                      painter: _WhiteboardPainter(
                        strokes: _strokes,
                        currentStroke: _currentStroke,
                      ),
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Mobile: Show toolbar toggle
          if (widget.isTeacher && !_showToolbar)
            Padding(
              padding: const EdgeInsets.all(8),
              child: ElevatedButton(
                onPressed: () => setState(() => _showToolbar = true),
                child: const Text('Show Tools'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSimpleToolbar() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.grey.shade200,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Pen tool
            _buildToolButton(Icons.brush, 'Pen', false),
            _buildToolButton(Icons.cleaning_services, 'Eraser', true),
            const SizedBox(width: 16),
            
            // Colors
            _buildColorButton(Colors.black),
            _buildColorButton(Colors.red),
            _buildColorButton(Colors.blue),
            _buildColorButton(Colors.green),
            const SizedBox(width: 16),
            
            // Stroke sizes
            _buildSizeButton(2.0),
            _buildSizeButton(4.0),
            _buildSizeButton(6.0),
            const SizedBox(width: 16),
            
            // Clear
            _buildClearButton(),
            
            // Hide toolbar
            _buildHideButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildToolButton(IconData icon, String label, bool isEraser) {
    final isSelected = _isEraser == isEraser;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ElevatedButton.icon(
        onPressed: () => setState(() => _isEraser = isEraser),
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected ? Colors.blue.shade100 : Colors.white,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    );
  }

  Widget _buildColorButton(Color color) {
    final isSelected = _selectedColor == color && !_isEraser;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedColor = color;
        _isEraser = false;
      }),
      child: Container(
        width: 30,
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey,
            width: isSelected ? 3 : 1,
          ),
        ),
      ),
    );
  }

  Widget _buildSizeButton(double size) {
    final isSelected = _strokeWidth == size;
    return GestureDetector(
      onTap: () => setState(() => _strokeWidth = size),
      child: Container(
        width: 30,
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade100 : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: isSelected ? Colors.blue : Colors.grey),
        ),
        child: Center(
          child: Container(
            width: size * 2,
            height: size * 2,
            decoration: BoxDecoration(
              color: _selectedColor,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClearButton() {
    return IconButton(
      icon: const Icon(Icons.delete, color: Colors.red),
      onPressed: () {
        setState(() => _strokes.clear());
      },
      tooltip: 'Clear',
    );
  }

  Widget _buildHideButton() {
    return IconButton(
      icon: const Icon(Icons.close),
      onPressed: () => setState(() => _showToolbar = false),
      tooltip: 'Hide tools',
    );
  }

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _currentStroke = _Stroke(
        points: [details.localPosition],
        color: _isEraser ? Colors.white : _selectedColor,
        strokeWidth: _isEraser ? _strokeWidth * 3 : _strokeWidth,
      );
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_currentStroke == null) return;
    setState(() {
      _currentStroke!.points.add(details.localPosition);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_currentStroke == null) return;
    setState(() {
      _strokes.add(_currentStroke!);
      _currentStroke = null;
    });
  }
}

class _Stroke {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;

  _Stroke({
    required this.points,
    required this.color,
    required this.strokeWidth,
  });
}

class _WhiteboardPainter extends CustomPainter {
  final List<_Stroke> strokes;
  final _Stroke? currentStroke;

  _WhiteboardPainter({
    required this.strokes,
    this.currentStroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw completed strokes
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }

    // Draw current stroke
    if (currentStroke != null) {
      _drawStroke(canvas, currentStroke!);
    }
  }

  void _drawStroke(Canvas canvas, _Stroke stroke) {
    if (stroke.points.isEmpty) return;

    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (stroke.points.length == 1) {
      // Draw a dot for single point
      canvas.drawCircle(stroke.points.first, stroke.strokeWidth / 2, paint);
      return;
    }

    final path = Path();
    path.moveTo(stroke.points.first.dx, stroke.points.first.dy);

    for (int i = 1; i < stroke.points.length; i++) {
      path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WhiteboardPainter oldDelegate) => true;
}