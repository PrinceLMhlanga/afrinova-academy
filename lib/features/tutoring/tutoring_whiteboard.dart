
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TutoringWhiteboard extends StatefulWidget {
  final String sessionId;
  final Map<String, dynamic>? initialSessionState;
  final Function(Map<String, dynamic>)? onStateChanged;
  
  const TutoringWhiteboard({
    super.key, 
    required this.sessionId,
    this.initialSessionState,
    this.onStateChanged,
  });

  @override
  State<TutoringWhiteboard> createState() => _TutoringWhiteboardState();
}

class _TutoringWhiteboardState extends State<TutoringWhiteboard> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final List<_StrokeData> _strokes = [];
  _StrokeData? _currentStroke;
  
  // Tool state
  late Color _color;
  late double _strokeWidth;
  late bool _isEraser;
  
  // Track deleted stroke IDs
  final Set<String> _deletedStrokeIds = {};
  DateTime? _lastClearTime;
  StreamSubscription? _strokeSubscription;
  StreamSubscription? _stateSubscription;

  // Canvas size
  Size _canvasSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _initToolState();
    _subscribeToState();
    _loadStrokes();
    _subscribeToStrokes();
  }

  void _initToolState() {
    final state = widget.initialSessionState;
    final colorValue = state?['wb_color'];
    if (colorValue is int) {
      _color = Color(colorValue);
    } else if (colorValue is String) {
      _color = Color(int.parse(colorValue));
    } else {
      _color = Colors.black;
    }
    _strokeWidth = (state?['wb_width'] as num?)?.toDouble() ?? 3.0;
    _isEraser = state?['wb_eraser'] ?? false;
  }

  void _subscribeToState() {
    _stateSubscription?.cancel();
    
    _stateSubscription = _supabase
        .from('tutoring_sessions')
        .stream(primaryKey: ['id'])
        .eq('id', widget.sessionId)
        .listen((data) {
      if (!mounted || data.isEmpty) return;
      
      final session = data.first;
      
      setState(() {
        final colorValue = session['wb_color'];
        if (colorValue is int) {
          _color = Color(colorValue);
        } else if (colorValue is String) {
          _color = Color(int.parse(colorValue));
        }
        _strokeWidth = (session['wb_width'] as num?)?.toDouble() ?? 3.0;
        _isEraser = session['wb_eraser'] ?? false;
      });
    });
  }

  Future<void> _updateToolState({
    Color? color,
    double? width,
    bool? eraser,
  }) async {
    final updates = <String, dynamic>{};
    
    if (color != null) {
      updates['wb_color'] = color.value;
      setState(() {
        _color = color;
        _isEraser = false;
      });
    }
    
    if (width != null) {
      updates['wb_width'] = width;
      setState(() {
        _strokeWidth = width;
        _isEraser = false;
      });
    }
    
    if (eraser != null) {
      updates['wb_eraser'] = eraser;
      setState(() => _isEraser = eraser);
    }
    
    if (updates.isNotEmpty) {
      try {
        await _supabase
            .from('tutoring_sessions')
            .update(updates)
            .eq('id', widget.sessionId);
        
        widget.onStateChanged?.call(updates);
      } catch (e) {
        debugPrint('❌ Failed to update tool state: $e');
      }
    }
  }

  Future<void> _loadStrokes() async {
    try {
      debugPrint('📥 Loading strokes from DB...');
      final data = await _supabase
          .from('tutoring_whiteboard')
          .select('*')
          .eq('session_id', widget.sessionId)
          .order('created_at', ascending: true);

      debugPrint('📥 Found ${data.length} strokes');
      
      if (!mounted) return;
      
      setState(() {
        _strokes.clear();
        _deletedStrokeIds.clear();
        for (final row in data) {
          _strokes.add(_parseStroke(row));
        }
      });
      
      debugPrint('📥 Loaded ${_strokes.length} strokes into local state');
    } catch (e) {
      debugPrint('❌ Load strokes error: $e');
    }
  }

  _StrokeData _parseStroke(Map<String, dynamic> row) {
    final strokeData = row['stroke_data'] as Map<String, dynamic>;
    
    // ✅ Get points - they could be absolute or relative
    final pointsData = strokeData['points'] as List;
    final List<Offset> points;
    
    if (pointsData.isNotEmpty) {
      final firstPoint = pointsData.first as Map<String, dynamic>;
      
      // ✅ Check if points are relative (0.0-1.0 range) or absolute
      final firstX = (firstPoint['x'] as num).toDouble();
      final firstY = (firstPoint['y'] as num).toDouble();
      
      if (firstX <= 1.0 && firstY <= 1.0 && _canvasSize.width > 0) {
        // Relative coordinates - convert to absolute
        debugPrint('🔄 Converting relative coordinates to absolute (canvas: ${_canvasSize.width}x${_canvasSize.height})');
        points = pointsData.map((p) {
          final px = (p['x'] as num).toDouble();
          final py = (p['y'] as num).toDouble();
          return Offset(px * _canvasSize.width, py * _canvasSize.height);
        }).toList();
      } else {
        // Absolute coordinates - use as-is
        points = pointsData.map((p) {
          return Offset(
            (p['x'] as num).toDouble(),
            (p['y'] as num).toDouble(),
          );
        }).toList();
      }
    } else {
      points = [];
    }
    
    final colorValue = strokeData['color'] as int?;
    final width = (strokeData['width'] as num?)?.toDouble() ?? 3.0;
    final isEraser = strokeData['is_eraser'] as bool? ?? false;
    
    return _StrokeData(
      id: row['id'] as String,
      points: points,
      color: colorValue != null ? Color(colorValue) : Colors.black,
      width: width,
      isEraser: isEraser,
      createdAt: row['created_at'] != null ? DateTime.parse(row['created_at'] as String) : null,
    );
  }

  void _subscribeToStrokes() {
    _strokeSubscription?.cancel();
    
    _strokeSubscription = _supabase
        .from('tutoring_whiteboard')
        .stream(primaryKey: ['id'])
        .eq('session_id', widget.sessionId)
        .order('created_at', ascending: true)
        .listen((data) {
      if (!mounted) return;
      
      debugPrint('🎧 Stream received ${data.length} strokes');
      
      // Filter out deleted strokes
      final filteredData = data.where((row) {
        return !_deletedStrokeIds.contains(row['id'] as String);
      }).toList();
      
      // If recently cleared, only accept new strokes
      if (_lastClearTime != null) {
        final timeSinceClear = DateTime.now().difference(_lastClearTime!);
        
        if (timeSinceClear.inSeconds < 3) {
          final newStrokesOnly = filteredData.where((row) {
            final createdAt = row['created_at'] as String?;
            if (createdAt == null) return false;
            return DateTime.parse(createdAt).isAfter(_lastClearTime!);
          }).toList();
          
          setState(() {
            _strokes.clear();
            for (final row in newStrokesOnly) {
              _strokes.add(_parseStroke(row));
            }
          });
          return;
        }
      }
      
      // Empty data means someone cleared
      if (data.isEmpty) {
        setState(() {
          _strokes.clear();
          _deletedStrokeIds.clear();
        });
        return;
      }
      
      setState(() {
        _strokes.clear();
        for (final row in filteredData) {
          _strokes.add(_parseStroke(row));
        }
      });
      
      debugPrint('🎧 Local state now has ${_strokes.length} strokes');
    });
  }

  Future<void> _saveStroke(List<Offset> points) async {
    try {
      _lastClearTime = null;
      
      debugPrint('💾 Saving stroke with ${points.length} points, canvas: ${_canvasSize.width}x${_canvasSize.height}');
      
      // ✅ Store points as relative coordinates (0.0 to 1.0)
      final relativePoints = _canvasSize.width > 0 && _canvasSize.height > 0
          ? points.map((p) => {
              'x': p.dx / _canvasSize.width,
              'y': p.dy / _canvasSize.height,
            }).toList()
          : points.map((p) => {'x': p.dx, 'y': p.dy}).toList();
      
      // ✅ Add to local state IMMEDIATELY with absolute points
      final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
      final newStroke = _StrokeData(
        id: tempId,
        points: List.from(points), // Absolute points for rendering
        color: _color,
        width: _isEraser ? 20.0 : _strokeWidth,
        isEraser: _isEraser,
        createdAt: DateTime.now(),
      );
      
      setState(() {
        _strokes.add(newStroke);
      });
      
      debugPrint('💾 Added to local state with temp ID: $tempId');
      
      // Save to database with relative points
      final result = await _supabase
          .from('tutoring_whiteboard')
          .insert({
            'session_id': widget.sessionId,
            'created_by': _supabase.auth.currentUser?.id,
            'stroke_data': {
              'points': relativePoints,
              'color': _color.value,
              'width': _isEraser ? 20.0 : _strokeWidth,
              'is_eraser': _isEraser,
            },
          })
          .select()
          .single();

      final realId = result['id'] as String;
      debugPrint('💾 Saved to DB with real ID: $realId');
      
      // Update temp ID with real ID (keep absolute points)
      setState(() {
        final index = _strokes.indexWhere((s) => s.id == tempId);
        if (index != -1) {
          _strokes[index] = _StrokeData(
            id: realId,
            points: newStroke.points, // Keep absolute points
            color: newStroke.color,
            width: newStroke.width,
            isEraser: newStroke.isEraser,
            createdAt: DateTime.parse(result['created_at'] as String),
          );
        }
      });
      
    } catch (e) {
      debugPrint('❌ Save stroke error: $e');
      setState(() {
        _strokes.removeWhere((s) => s.id?.startsWith('temp_') == true);
      });
    }
  }

  Future<void> _clearWhiteboard() async {
    try {
      debugPrint('🧹 Clearing whiteboard...');
      
      final idsToDelete = _strokes.map((s) => s.id).whereType<String>().toSet();
      _deletedStrokeIds.addAll(idsToDelete);
      _lastClearTime = DateTime.now();
      
      setState(() {
        _strokes.clear();
        _currentStroke = null;
      });
      
      await _supabase
          .from('tutoring_whiteboard')
          .delete()
          .eq('session_id', widget.sessionId);
      
      debugPrint('🧹 Deleted from DB, verifying...');
      
      await Future.delayed(const Duration(milliseconds: 300));
      final remaining = await _supabase
          .from('tutoring_whiteboard')
          .select('id')
          .eq('session_id', widget.sessionId);
      
      if (remaining.isNotEmpty) {
        debugPrint('⚠️ ${remaining.length} strokes remaining, force deleting...');
        for (final row in remaining) {
          await _supabase
              .from('tutoring_whiteboard')
              .delete()
              .eq('id', row['id']);
        }
      }
      
      debugPrint('✅ Clear complete');
      
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _lastClearTime = null;
      });
    } catch (e) {
      debugPrint('❌ Clear error: $e');
      _lastClearTime = null;
      _loadStrokes();
    }
  }

  @override
  void dispose() {
    _strokeSubscription?.cancel();
    _stateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Scrollable toolbar
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                _buildToolButton(
                  icon: Icons.brush,
                  isSelected: !_isEraser,
                  onTap: () => _updateToolState(eraser: false),
                  tooltip: 'Pen',
                ),
                _buildToolButton(
                  icon: Icons.cleaning_services,
                  isSelected: _isEraser,
                  onTap: () => _updateToolState(eraser: true),
                  tooltip: 'Eraser',
                ),
                
                const SizedBox(width: 12),
                _buildDivider(),
                const SizedBox(width: 12),
                
                if (!_isEraser) ...[
                  _buildColorDot(Colors.black),
                  _buildColorDot(Colors.red),
                  _buildColorDot(Colors.blue),
                  _buildColorDot(Colors.green),
                  _buildColorDot(Colors.orange),
                  _buildColorDot(Colors.purple),
                  
                  const SizedBox(width: 12),
                  _buildDivider(),
                  const SizedBox(width: 12),
                  
                  _buildStrokeWidthButton(2.0),
                  _buildStrokeWidthButton(4.0),
                  _buildStrokeWidthButton(6.0),
                ],
                
                const SizedBox(width: 12),
                _buildDivider(),
                const SizedBox(width: 12),
                
                _buildToolButton(
                  icon: Icons.delete_outline,
                  isSelected: false,
                  onTap: _clearWhiteboard,
                  tooltip: 'Clear All',
                  iconColor: Colors.red,
                ),
              ],
            ),
          ),
        ),
        
        // Drawing area
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // ✅ Update canvas size when layout changes
              final newSize = Size(constraints.maxWidth, constraints.maxHeight);
              if (newSize != _canvasSize && newSize.width > 0 && newSize.height > 0) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _canvasSize != newSize) {
                    setState(() {
                      _canvasSize = newSize;
                    });
                    // ✅ Reload strokes with new canvas size for proper coordinate conversion
                    _loadStrokes();
                  }
                });
              }
              
              return ClipRect(
                child: GestureDetector(
                  onPanStart: (details) {
                    _lastClearTime = null;
                    final pos = Offset(
                      details.localPosition.dx.clamp(0.0, constraints.maxWidth),
                      details.localPosition.dy.clamp(0.0, constraints.maxHeight),
                    );
                    setState(() {
                      _currentStroke = _StrokeData(
                        points: [pos],
                        color: _color,
                        width: _isEraser ? 20.0 : _strokeWidth,
                        isEraser: _isEraser,
                      );
                    });
                  },
                  onPanUpdate: (details) {
                    final pos = Offset(
                      details.localPosition.dx.clamp(0.0, constraints.maxWidth),
                      details.localPosition.dy.clamp(0.0, constraints.maxHeight),
                    );
                    setState(() {
                      _currentStroke?.points.add(pos);
                    });
                  },
                  onPanEnd: (details) {
                    if (_currentStroke != null && _currentStroke!.points.length > 1) {
                      _saveStroke(List.from(_currentStroke!.points));
                    }
                    _currentStroke = null;
                  },
                  child: Container(
                    color: Colors.white,
                    child: CustomPaint(
                      painter: _WhiteboardPainter(
                        strokes: _strokes,
                        currentStroke: _currentStroke,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(width: 1, height: 24, color: Colors.grey.shade300);
  }

  Widget _buildToolButton({
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required String tooltip,
    Color? iconColor,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isSelected ? Border.all(color: Colors.blue.withOpacity(0.3)) : null,
            ),
            child: Icon(
              icon,
              size: 20,
              color: iconColor ?? (isSelected ? Colors.blue : Colors.grey.shade700),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildColorDot(Color color) {
    final isSelected = _color.value == color.value && !_isEraser;
    return Tooltip(
      message: _getColorName(color),
      child: GestureDetector(
        onTap: () => _updateToolState(color: color),
        child: Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? Colors.blue : Colors.grey.shade400,
              width: isSelected ? 3 : 1.5,
            ),
            boxShadow: isSelected
                ? [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 4)]
                : null,
          ),
        ),
      ),
    );
  }

  String _getColorName(Color color) {
    if (color == Colors.black) return 'Black';
    if (color == Colors.red) return 'Red';
    if (color == Colors.blue) return 'Blue';
    if (color == Colors.green) return 'Green';
    if (color == Colors.orange) return 'Orange';
    if (color == Colors.purple) return 'Purple';
    return 'Color';
  }

  Widget _buildStrokeWidthButton(double width) {
    final isSelected = _strokeWidth == width && !_isEraser;
    return Tooltip(
      message: '${width.toInt()}px',
      child: GestureDetector(
        onTap: () => _updateToolState(width: width),
        child: Container(
          width: 32,
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: isSelected
                ? Border.all(color: Colors.blue.withOpacity(0.3))
                : Border.all(color: Colors.transparent),
          ),
          child: Center(
            child: Container(
              width: width * 2,
              height: width * 2,
              decoration: BoxDecoration(
                color: _color,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StrokeData {
  final String? id;
  final List<Offset> points;
  final Color color;
  final double width;
  final bool isEraser;
  final DateTime? createdAt;

  _StrokeData({
    this.id,
    required this.points,
    required this.color,
    required this.width,
    this.isEraser = false,
    this.createdAt,
  });
}

class _WhiteboardPainter extends CustomPainter {
  final List<_StrokeData> strokes;
  final _StrokeData? currentStroke;

  _WhiteboardPainter({
    required this.strokes,
    this.currentStroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }
    if (currentStroke != null) _drawStroke(canvas, currentStroke!);
  }

  void _drawStroke(Canvas canvas, _StrokeData stroke) {
    if (stroke.points.isEmpty) return;

    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (stroke.isEraser) {
      paint
        ..blendMode = BlendMode.clear
        ..color = Colors.transparent
        ..strokeWidth = stroke.width;
    } else {
      paint
        ..color = stroke.color
        ..strokeWidth = stroke.width
        ..blendMode = BlendMode.srcOver;
    }

    final path = Path();
    path.moveTo(stroke.points.first.dx, stroke.points.first.dy);
    
    for (int i = 1; i < stroke.points.length; i++) {
      final p0 = stroke.points[i - 1];
      final p1 = stroke.points[i];
      path.quadraticBezierTo(
        p0.dx,
        p0.dy,
        (p0.dx + p1.dx) / 2,
        (p0.dy + p1.dy) / 2,
      );
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WhiteboardPainter old) => true;
}