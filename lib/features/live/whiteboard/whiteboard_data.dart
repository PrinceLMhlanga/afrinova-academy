import 'dart:ui';

enum StrokeType { draw, line, rectangle, circle, eraser }

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

  // ✅ Use the LARGER scale to maximize drawing area
  Map<String, dynamic> toJson(Size canvasSize) {
    return {
      'id': id,
      'points': points.map((p) => {
        'x': p.dx / canvasSize.width,
        'y': p.dy / canvasSize.height,
      }).toList(),
      'color': color.value,
      'strokeWidth': strokeWidth / canvasSize.width,
      'type': type.index,
      'aspectRatio': canvasSize.width / canvasSize.height,
      'width': canvasSize.width,
      'height': canvasSize.height,
    };
  }

  factory WhiteboardStroke.fromJson(Map<String, dynamic> json, Size canvasSize) {
    final senderWidth = (json['width'] as num?)?.toDouble() ?? canvasSize.width;
    final senderHeight = (json['height'] as num?)?.toDouble() ?? canvasSize.height;
    final senderAspectRatio = senderWidth / senderHeight;
    final receiverAspectRatio = canvasSize.width / canvasSize.height;
    
    // ✅ Calculate scale that MAXIMIZES the drawing area
    double scaleX, scaleY, offsetX = 0, offsetY = 0;
    
    if (senderAspectRatio > receiverAspectRatio) {
      // Sender is wider - fit by width, letterbox vertically
      scaleX = canvasSize.width / senderWidth;
      scaleY = scaleX; // Same scale to preserve aspect ratio
      final scaledHeight = senderHeight * scaleY;
      offsetY = (canvasSize.height - scaledHeight) / 2;
    } else {
      // Sender is taller - fit by height, letterbox horizontally
      scaleY = canvasSize.height / senderHeight;
      scaleX = scaleY; // Same scale to preserve aspect ratio
      final scaledWidth = senderWidth * scaleX;
      offsetX = (canvasSize.width - scaledWidth) / 2;
    }
    
    // ✅ Scale stroke width proportionally
    final strokeScale = (scaleX + scaleY) / 2;
    
    return WhiteboardStroke(
      id: json['id'],
      points: (json['points'] as List)
          .map((p) => Offset(
            (p['x'] as num).toDouble() * senderWidth * scaleX + offsetX,
            (p['y'] as num).toDouble() * senderHeight * scaleY + offsetY,
          ))
          .toList(),
      color: Color(json['color'] as int),
      strokeWidth: (json['strokeWidth'] as num).toDouble() * senderWidth * strokeScale,
      type: StrokeType.values[json['type'] as int],
    );
  }
}