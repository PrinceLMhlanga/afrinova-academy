import 'dart:convert';
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
    'color': color.value,
    'strokeWidth': strokeWidth,
    'type': type.index,
  };

  factory WhiteboardStroke.fromJson(Map<String, dynamic> json) {
    return WhiteboardStroke(
      id: json['id'],
      points: (json['points'] as List)
          .map((p) => Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
          .toList(),
      color: Color(json['color'] as int),
      strokeWidth: (json['strokeWidth'] as num).toDouble(),
      type: StrokeType.values[json['type'] as int],
    );
  }
}

enum StrokeType { draw, line, rectangle, circle, eraser }

class WhiteboardState {
  final List<WhiteboardStroke> strokes;
  final String lastUpdatedBy;

  WhiteboardState({
    required this.strokes,
    required this.lastUpdatedBy,
  });

  Map<String, dynamic> toJson() => {
    'strokes': strokes.map((s) => s.toJson()).toList(),
    'lastUpdatedBy': lastUpdatedBy,
  };

  factory WhiteboardState.fromJson(Map<String, dynamic> json) {
    return WhiteboardState(
      strokes: (json['strokes'] as List)
          .map((s) => WhiteboardStroke.fromJson(s))
          .toList(),
      lastUpdatedBy: json['lastUpdatedBy'] ?? '',
    );
  }
}