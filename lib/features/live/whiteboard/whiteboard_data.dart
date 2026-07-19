
import 'package:flutter/material.dart';

class WhiteboardStroke {
  final String id;
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final StrokeType type;

  WhiteboardStroke({
    required this.id,
    required this.points,
    required this.color,
    required this.strokeWidth,
    this.type = StrokeType.draw,
  });

  // ✅ Convert absolute coordinates to normalized (0.0 to 1.0)
  Map<String, dynamic> toJson(Size canvasSize) => {
    'id': id,
    'points': points.map((p) => {
      'x': p.dx / canvasSize.width,
      'y': p.dy / canvasSize.height,
    }).toList(),
    'color': color.value,
    'strokeWidth': strokeWidth,
    'type': type.index,
  };

  // ✅ Convert normalized coordinates back to absolute
  factory WhiteboardStroke.fromJson(Map<String, dynamic> json, Size canvasSize) {
    return WhiteboardStroke(
      id: json['id'],
      points: (json['points'] as List)
          .map((p) => Offset(
            (p['x'] as num).toDouble() * canvasSize.width,
            (p['y'] as num).toDouble() * canvasSize.height,
          ))
          .toList(),
      color: Color(json['color'] as int),
      strokeWidth: (json['strokeWidth'] as num).toDouble(),
      type: StrokeType.values[json['type'] as int],
    );
  }
}

enum StrokeType { draw, line, rectangle, circle, eraser }

