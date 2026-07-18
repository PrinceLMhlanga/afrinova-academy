import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'whiteboard_data.dart';
import 'whiteboard_painter.dart';

class WhiteboardCanvas extends StatefulWidget {
  final Room room;
  final bool isTeacher;
  final String userName;
  final VoidCallback? onDrawingStart;  // ✅ Add this
  final VoidCallback? onDrawingEnd;    // ✅ Add this

  const WhiteboardCanvas({
    super.key,
    required this.room,
    required this.isTeacher,
    required this.userName,
    this.onDrawingStart,
    this.onDrawingEnd,
  });

  @override
  State<WhiteboardCanvas> createState() => _WhiteboardCanvasState();
}

class _WhiteboardCanvasState extends State<WhiteboardCanvas> {
  final List<WhiteboardStroke> _strokes = [];
  WhiteboardStroke? _currentStroke;
  
  Color _selectedColor = Colors.black;
  double _strokeWidth = 3.0;
  StrokeType _currentTool = StrokeType.draw;
  
  final Map<String, Color> _colorPalette = {
    'Black': Colors.black,
    'Red': Colors.red,
    'Blue': Colors.blue,
    'Green': Colors.green,
    'Orange': Colors.orange,
    'Purple': Colors.purple,
  };

  final Map<String, double> _strokeSizes = {
    'Thin': 2.0,
    'Medium': 4.0,
    'Thick': 8.0,
  };

  @override
  void initState() {
    super.initState();
    _setupDataSync();
  }

  void _setupDataSync() {
    // Listen for whiteboard data from other participants
    widget.room.addListener(() {
      // This would be replaced with LiveKit data channel messages
    });
  }

  void _sendWhiteboardUpdate(WhiteboardStroke stroke) {
    final data = jsonEncode({
      'type': 'whiteboard_stroke',
      'stroke': stroke.toJson(),
      'sentBy': widget.userName,
    });
    
    // Send via LiveKit data channel
    widget.room.localParticipant?.publishData(
      utf8.encode(data),
      reliable: true,
    );
  }

  void _onPanStart(DragStartDetails details) {
  if (!widget.isTeacher) return;
  
  widget.onDrawingStart?.call();  // ✅ Notify parent
  
  final id = DateTime.now().millisecondsSinceEpoch.toString();
  setState(() {
    _currentStroke = WhiteboardStroke(
      id: id,
      points: [details.localPosition],
      color: _currentTool == StrokeType.eraser ? Colors.white : _selectedColor,
      strokeWidth: _strokeWidth,
      type: _currentTool,
    );
  });
}

void _onPanEnd(DragEndDetails details) {
  if (!widget.isTeacher || _currentStroke == null) return;
  
  setState(() {
    _strokes.add(_currentStroke!);
    _sendWhiteboardUpdate(_currentStroke!);
    _currentStroke = null;
  });
  
  widget.onDrawingEnd?.call();  // ✅ Notify parent
}

  void _onPanUpdate(DragUpdateDetails details) {
    if (!widget.isTeacher || _currentStroke == null) return;
    
    setState(() {
      _currentStroke!.points.add(details.localPosition);
    });
  }

  

  void _clearWhiteboard() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Whiteboard?'),
        content: const Text('This will remove all drawings.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _strokes.clear());
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          if (widget.isTeacher) _buildToolbar(),
          Expanded(
            child: GestureDetector(
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: ClipRRect(
                child: CustomPaint(
                  painter: WhiteboardPainter(
                    strokes: _strokes,
                    currentStroke: _currentStroke,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          // Tools
          _buildToolButton(Icons.brush, 'Draw', StrokeType.draw),
          _buildToolButton(Icons.show_chart, 'Line', StrokeType.line),
          _buildToolButton(Icons.crop_square, 'Rect', StrokeType.rectangle),
          _buildToolButton(Icons.circle_outlined, 'Circle', StrokeType.circle),
          _buildToolButton(Icons.auto_fix_high, 'Eraser', StrokeType.eraser),
          
          const SizedBox(width: 16),
          Container(width: 1, height: 24, color: Colors.grey.shade400),
          const SizedBox(width: 16),
          
          // Colors
          ..._colorPalette.entries.map((entry) => _buildColorButton(entry.value, entry.key)),
          
          const SizedBox(width: 16),
          Container(width: 1, height: 24, color: Colors.grey.shade400),
          const SizedBox(width: 16),
          
          // Stroke sizes
          ..._strokeSizes.entries.map((entry) => _buildSizeButton(entry.value, entry.key)),
          
          const Spacer(),
          
          // Clear button
          _buildActionButton(Icons.delete_outline, 'Clear', _clearWhiteboard, Colors.red),
        ],
      ),
    );
  }

  Widget _buildToolButton(IconData icon, String tooltip, StrokeType type) {
    final isSelected = _currentTool == type;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: isSelected ? Colors.blue.shade50 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _currentTool = type),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                icon,
                size: 20,
                color: isSelected ? Colors.blue : Colors.grey.shade700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildColorButton(Color color, String tooltip) {
    final isSelected = _selectedColor == color && _currentTool != StrokeType.eraser;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: () => setState(() {
            _selectedColor = color;
            _currentTool = StrokeType.draw;
          }),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.blue : Colors.grey.shade400,
                width: isSelected ? 3 : 1,
              ),
              boxShadow: isSelected
                  ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 4)]
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSizeButton(double size, String tooltip) {
    final isSelected = _strokeWidth == size;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: () => setState(() => _strokeWidth = size),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isSelected ? Colors.blue.shade50 : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected ? Colors.blue : Colors.transparent,
              ),
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
        ),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String tooltip, VoidCallback onPressed, Color color) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 20, color: color),
          ),
        ),
      ),
    );
  }
}