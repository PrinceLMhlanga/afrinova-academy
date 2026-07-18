import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'whiteboard_data.dart';
import 'whiteboard_painter.dart';

class WhiteboardCanvas extends StatefulWidget {
  final Room room;
  final bool isTeacher;
  final String userName;
  final VoidCallback? onDrawingStart;
  final VoidCallback? onDrawingEnd;

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
  
  late final EventsListener<RoomEvent> _roomListener;
  
  
  

  @override
  void initState() {
    super.initState();
    _setupDataChannel();
  }

  void _setupDataChannel() {
  _roomListener = widget.room.createListener();
  
  _roomListener.on<DataReceivedEvent>((event) {
    final data = event.data is Uint8List 
        ? event.data as Uint8List 
        : Uint8List.fromList(event.data);
    _handleDataMessage(data);
  });
}

  void _handleDataMessage(Uint8List data) {
    try {
      final message = jsonDecode(utf8.decode(data));
      
      if (message['type'] == 'whiteboard_stroke') {
        final stroke = WhiteboardStroke.fromJson(message['stroke']);
        if (mounted) {
          setState(() {
            _strokes.removeWhere((s) => s.id == stroke.id);
            _strokes.add(stroke);
          });
        }
      } else if (message['type'] == 'whiteboard_clear') {
        if (mounted) {
          setState(() {
            _strokes.clear();
          });
        }
      }
    } catch (e) {
      debugPrint('Error handling whiteboard data: $e');
    }
  }

  void _sendStroke(WhiteboardStroke stroke) {
    final data = utf8.encode(jsonEncode({
      'type': 'whiteboard_stroke',
      'stroke': stroke.toJson(),
      'sentBy': widget.userName,
    }));
    
    widget.room.localParticipant?.publishData(
      data,
      reliable: true,
      topic: 'whiteboard',  // Topic for filtering
    );
  }

  void _sendClear() {
    final data = utf8.encode(jsonEncode({
      'type': 'whiteboard_clear',
      'sentBy': widget.userName,
    }));
    
    widget.room.localParticipant?.publishData(
      data,
      reliable: true,
      topic: 'whiteboard',
    );
  }

  // In _WhiteboardCanvasState, remove the toolbar hiding logic:

void _onPanStart(DragStartDetails details) {
  if (!widget.isTeacher) return;
  
  widget.onDrawingStart?.call();
  
  final id = '${DateTime.now().millisecondsSinceEpoch}_${widget.userName}';
  setState(() {
    _currentStroke = WhiteboardStroke(
      id: id,
      points: [details.localPosition],
      color: _currentTool == StrokeType.eraser ? Colors.white : _selectedColor,
      strokeWidth: _strokeWidth,
      type: _currentTool,
    );
    // ❌ REMOVE THIS: Don't hide toolbar
    // if (MediaQuery.of(context).size.width < 600) {
    //   _showToolbar = false;
    // }
  });
}

void _onPanEnd(DragEndDetails details) {
  if (!widget.isTeacher || _currentStroke == null) return;
  
  setState(() {
    _strokes.add(_currentStroke!);
    _sendStroke(_currentStroke!);
    _currentStroke = null;
    // ❌ REMOVE THIS: Toolbar stays visible
    // _showToolbar = true;
  });
  
  widget.onDrawingEnd?.call();
}

  void _onPanUpdate(DragUpdateDetails details) {
    if (!widget.isTeacher || _currentStroke == null) return;
    
    setState(() {
      _currentStroke!.points.add(details.localPosition);
    });
  }

 

  void _clearWhiteboard() {
    if (!widget.isTeacher) return;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Whiteboard?'),
        content: const Text('This will remove all drawings for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _strokes.clear());
              _sendClear();  // Notify all participants
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _roomListener.dispose();
    super.dispose();
  }

 @override
Widget build(BuildContext context) {
  final isMobile = MediaQuery.of(context).size.width < 600;
  
  return Container(
    color: Colors.white,
    child: Column(
      children: [
        // Toolbar - always visible for teacher
        if (widget.isTeacher)
          isMobile ? _buildMobileToolbar() : _buildDesktopToolbar(),
        
        // Canvas area
        Expanded(
          child: GestureDetector(
            onPanStart: widget.isTeacher ? _onPanStart : null,
            onPanUpdate: widget.isTeacher ? _onPanUpdate : null,
            onPanEnd: widget.isTeacher ? _onPanEnd : null,
            child: Container(
              color: Colors.white,
              width: double.infinity,
              height: double.infinity,
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
  Widget _buildToolbar(bool isMobile) {
    if (isMobile) {
      return _buildMobileToolbar();
    }
    return _buildDesktopToolbar();
  }

  Widget _buildDesktopToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          // Tools
          _buildToolChip(Icons.brush, 'Draw', StrokeType.draw),
          _buildToolChip(Icons.show_chart, 'Line', StrokeType.line),
          _buildToolChip(Icons.crop_square, 'Rect', StrokeType.rectangle),
          _buildToolChip(Icons.circle_outlined, 'Circle', StrokeType.circle),
          _buildToolChip(Icons.auto_fix_high, 'Eraser', StrokeType.eraser),
          
          const SizedBox(width: 8),
          
          // Colors
          ...[Colors.black, Colors.red, Colors.blue, Colors.green, Colors.orange, Colors.purple]
              .map((c) => _buildColorDot(c)),
          
          const SizedBox(width: 8),
          
          // Sizes
          _buildSizeChip(2.0, 'S'),
          _buildSizeChip(4.0, 'M'),
          _buildSizeChip(8.0, 'L'),
          
          const SizedBox(width: 8),
          
          // Clear
          _buildActionChip(Icons.delete, 'Clear', Colors.red, _clearWhiteboard),
        ],
      ),
    );
  }

  Widget _buildMobileToolbar() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // All drawing tools
          _buildCompactToolButton(Icons.brush, StrokeType.draw),
          _buildCompactToolButton(Icons.show_chart, StrokeType.line),
          _buildCompactToolButton(Icons.crop_square, StrokeType.rectangle),
          _buildCompactToolButton(Icons.circle_outlined, StrokeType.circle),
          _buildCompactToolButton(Icons.auto_fix_high, StrokeType.eraser),
          
          Container(width: 1, height: 24, color: Colors.grey.shade300),
          const SizedBox(width: 4),
          
          // All colors
          ...<Color>[Colors.black, Colors.red, Colors.blue, Colors.green, Colors.orange, Colors.purple]
              .map((c) => _buildCompactColorDot(c)),
          
          Container(width: 1, height: 24, color: Colors.grey.shade300),
          const SizedBox(width: 4),
          
          // All stroke sizes
          _buildCompactSizeButton(2.0),
          _buildCompactSizeButton(4.0),
          _buildCompactSizeButton(8.0),
          
          Container(width: 1, height: 24, color: Colors.grey.shade300),
          const SizedBox(width: 4),
          
          // Clear button
          _buildCompactActionButton(Icons.delete_outline, Colors.red, _clearWhiteboard),
        ],
      ),
    ),
  );
}

// Compact tool button
Widget _buildCompactToolButton(IconData icon, StrokeType type) {
  final isSelected = _currentTool == type;
  return GestureDetector(
    onTap: () => setState(() => _currentTool = type),
    child: Container(
      padding: const EdgeInsets.all(6),
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: isSelected ? Colors.blue.shade100 : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isSelected ? Border.all(color: Colors.blue, width: 1.5) : null,
      ),
      child: Icon(
        icon,
        size: 18,
        color: isSelected ? Colors.blue : Colors.grey.shade700,
      ),
    ),
  );
}

// Compact color dot
Widget _buildCompactColorDot(Color color) {
  final isSelected = _selectedColor == color && _currentTool != StrokeType.eraser;
  return GestureDetector(
    onTap: () => setState(() {
      _selectedColor = color;
      _currentTool = StrokeType.draw;
    }),
    child: Container(
      width: 22,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? Colors.blue : Colors.grey.shade400,
          width: isSelected ? 2.5 : 1,
        ),
        boxShadow: isSelected
            ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 4)]
            : null,
      ),
    ),
  );
}

// Compact size button
Widget _buildCompactSizeButton(double size) {
  final isSelected = _strokeWidth == size;
  return GestureDetector(
    onTap: () => setState(() => _strokeWidth = size),
    child: Container(
      width: 26,
      height: 26,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: isSelected ? Colors.blue.shade50 : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: isSelected ? Colors.blue : Colors.grey.shade300,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Center(
        child: Container(
          width: size * 1.5,
          height: size * 1.5,
          decoration: BoxDecoration(
            color: _selectedColor,
            shape: BoxShape.circle,
          ),
        ),
      ),
    ),
  );
}

// Compact action button
Widget _buildCompactActionButton(IconData icon, Color color, VoidCallback onPressed) {
  return GestureDetector(
    onTap: onPressed,
    child: Container(
      padding: const EdgeInsets.all(6),
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 18, color: color),
    ),
  );
}

  Widget _buildToolChip(IconData icon, String label, StrokeType type) {
    final isSelected = _currentTool == type;
    return Material(
      color: isSelected ? Colors.blue.shade100 : Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: isSelected ? 2 : 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => _currentTool = type),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: isSelected ? Colors.blue : Colors.black87),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(label, style: TextStyle(fontSize: 12, color: isSelected ? Colors.blue : Colors.black87)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorDot(Color color) {
    final isSelected = _selectedColor == color && _currentTool != StrokeType.eraser;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedColor = color;
        _currentTool = StrokeType.draw;
      }),
      child: Container(
        width: 28,
        height: 28,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey.shade400,
            width: isSelected ? 3 : 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildSizeChip(double size, String label) {
    final isSelected = _strokeWidth == size;
    return GestureDetector(
      onTap: () => setState(() => _strokeWidth = size),
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade100 : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey.shade300,
          ),
        ),
        child: Center(
          child: Container(
            width: size * 1.5,
            height: size * 1.5,
            decoration: BoxDecoration(
              color: _selectedColor,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionChip(IconData icon, String label, Color color, VoidCallback onPressed) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(label, style: TextStyle(fontSize: 12, color: color)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}