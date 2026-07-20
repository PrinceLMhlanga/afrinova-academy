import 'package:flutter/material.dart';
import 'whiteboard_data.dart';

class WhiteboardPainter extends CustomPainter {
  final List<WhiteboardStroke> strokes;
  final WhiteboardStroke? currentStroke;

  WhiteboardPainter({
    required this.strokes,
    this.currentStroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ✅ Draw subtle background grid to show drawing area
    _drawBackground(canvas, size);
    
    // Draw completed strokes
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }

    // Draw current stroke
    if (currentStroke != null) {
      _drawStroke(canvas, currentStroke!);
    }
  }

  void _drawBackground(Canvas canvas, Size size) {
    // Optional: Draw light border to show the drawing area
    final paint = Paint()
      ..color = Colors.grey.shade200
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  void _drawStroke(Canvas canvas, WhiteboardStroke stroke) {
    if (stroke.points.isEmpty) return;

    final paint = Paint()
      ..color = stroke.type == StrokeType.eraser ? Colors.white : stroke.color
      ..strokeWidth = stroke.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    switch (stroke.type) {
      case StrokeType.draw:
      case StrokeType.eraser:
        _drawFreehand(canvas, stroke.points, paint);
        break;
      case StrokeType.line:
        _drawLine(canvas, stroke.points, paint);
        break;
      case StrokeType.rectangle:
        _drawRectangle(canvas, stroke.points, paint);
        break;
      case StrokeType.circle:
        _drawCircle(canvas, stroke.points, paint);
        break;
    }
  }

  void _drawFreehand(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length < 2) {
      canvas.drawCircle(points.first, paint.strokeWidth / 2, paint);
      return;
    }

    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);

    for (int i = 1; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      path.quadraticBezierTo(
        p0.dx, p0.dy,
        (p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2,
      );
    }
    path.lineTo(points.last.dx, points.last.dy);
    canvas.drawPath(path, paint);
  }

  void _drawLine(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length >= 2) {
      canvas.drawLine(points.first, points.last, paint);
    }
  }

  void _drawRectangle(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length >= 2) {
      final rect = Rect.fromPoints(points.first, points.last);
      canvas.drawRect(rect, paint);
    }
  }

  void _drawCircle(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length >= 2) {
      final center = points.first;
      final radius = (points.last - points.first).distance;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant WhiteboardPainter oldDelegate) => true;
}