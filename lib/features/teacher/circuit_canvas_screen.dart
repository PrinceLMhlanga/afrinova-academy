import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class CircuitCanvasScreen extends StatefulWidget {
  final void Function(String svgMarkup) onInsert;

  const CircuitCanvasScreen({super.key, required this.onInsert});

  @override
  State<CircuitCanvasScreen> createState() => _CircuitCanvasScreenState();
}

class _CircuitCanvasScreenState extends State<CircuitCanvasScreen> {
  final GlobalKey _canvasKey = GlobalKey();
  Offset? _lastGlobalPointerPosition;

  final Map<String, _ComponentSpec> _components = {
    'Resistor': const _ComponentSpec(
      name: 'Resistor',
      svg: '''
        <svg viewBox="0 0 100 40">
          <line x1="0" y1="20" x2="15" y2="20" stroke="black" stroke-width="2"/>
          <rect x="15" y="5" width="70" height="30" rx="3" fill="white" stroke="black" stroke-width="2"/>
          <line x1="85" y1="20" x2="100" y2="20" stroke="black" stroke-width="2"/>
        </svg>
      ''',
      width: 100,
      height: 40,
    ),
    'Battery': const _ComponentSpec(
      name: 'Battery',
      svg: '''
        <svg viewBox="0 0 100 50">
          <line x1="0" y1="25" x2="20" y2="25" stroke="black" stroke-width="2"/>
          <rect x="20" y="5" width="60" height="40" rx="5" fill="white" stroke="black" stroke-width="2"/>
          <line x1="30" y1="20" x2="30" y2="30" stroke="black" stroke-width="3"/>
          <line x1="35" y1="15" x2="35" y2="35" stroke="black" stroke-width="3"/>
          <line x1="80" y1="25" x2="100" y2="25" stroke="black" stroke-width="2"/>
        </svg>
      ''',
      width: 100,
      height: 50,
    ),
    'Switch': const _ComponentSpec(
      name: 'Switch',
      svg: '''
        <svg viewBox="0 0 100 50">
          <circle cx="20" cy="25" r="3" fill="black"/>
          <line x1="0" y1="25" x2="20" y2="25" stroke="black" stroke-width="2"/>
          <circle cx="80" cy="25" r="3" fill="black"/>
          <line x1="80" y1="25" x2="100" y2="25" stroke="black" stroke-width="2"/>
          <line x1="20" y1="25" x2="60" y2="10" stroke="black" stroke-width="2"/>
        </svg>
      ''',
      width: 100,
      height: 50,
    ),
    'Ammeter': const _ComponentSpec(
      name: 'Ammeter',
      svg: '''
        <svg viewBox="0 0 100 50">
          <circle cx="50" cy="25" r="22" fill="white" stroke="black" stroke-width="2"/>
          <text x="50" y="31" text-anchor="middle" font-size="16" font-weight="bold" fill="black">A</text>
          <line x1="0" y1="25" x2="28" y2="25" stroke="black" stroke-width="2"/>
          <line x1="72" y1="25" x2="100" y2="25" stroke="black" stroke-width="2"/>
        </svg>
      ''',
      width: 100,
      height: 50,
    ),
    'Voltmeter': const _ComponentSpec(
      name: 'Voltmeter',
      svg: '''
        <svg viewBox="0 0 100 50">
          <circle cx="50" cy="25" r="22" fill="white" stroke="black" stroke-width="2"/>
          <text x="50" y="31" text-anchor="middle" font-size="16" font-weight="bold" fill="black">V</text>
          <line x1="0" y1="25" x2="28" y2="25" stroke="black" stroke-width="2"/>
          <line x1="72" y1="25" x2="100" y2="25" stroke="black" stroke-width="2"/>
        </svg>
      ''',
      width: 100,
      height: 50,
    ),
    'Bulb': const _ComponentSpec(
      name: 'Bulb',
      svg: '''
        <svg viewBox="0 0 60 80">
          <circle cx="30" cy="30" r="22" fill="white" stroke="black" stroke-width="2"/>
          <line x1="18" y1="52" x2="42" y2="52" stroke="black" stroke-width="2"/>
          <line x1="21" y1="56" x2="39" y2="56" stroke="black" stroke-width="2"/>
          <line x1="24" y1="60" x2="36" y2="60" stroke="black" stroke-width="2"/>
          <line x1="30" y1="60" x2="30" y2="80" stroke="black" stroke-width="2"/>
          <line x1="0" y1="30" x2="8" y2="30" stroke="black" stroke-width="2"/>
        </svg>
      ''',
      width: 60,
      height: 80,
    ),
    'Diode': const _ComponentSpec(
      name: 'Diode',
      svg: '''
        <svg viewBox="0 0 100 50">
          <line x1="0" y1="25" x2="25" y2="25" stroke="black" stroke-width="2"/>
          <polygon points="25,10 55,25 25,40" fill="white" stroke="black" stroke-width="2"/>
          <line x1="55" y1="10" x2="55" y2="40" stroke="black" stroke-width="2"/>
          <line x1="55" y1="25" x2="100" y2="25" stroke="black" stroke-width="2"/>
        </svg>
      ''',
      width: 100,
      height: 50,
    ),
    'Ground': const _ComponentSpec(
      name: 'Ground',
      svg: '''
        <svg viewBox="0 0 50 50">
          <line x1="25" y1="0" x2="25" y2="15" stroke="black" stroke-width="2"/>
          <line x1="5" y1="15" x2="45" y2="15" stroke="black" stroke-width="2"/>
          <line x1="12" y1="25" x2="38" y2="25" stroke="black" stroke-width="2"/>
          <line x1="17" y1="35" x2="33" y2="35" stroke="black" stroke-width="2"/>
        </svg>
      ''',
      width: 50,
      height: 50,
    ),
    'Wire': const _ComponentSpec(
      name: 'Wire',
      svg: '''
        <svg viewBox="0 0 80 12">
          <line x1="0" y1="6" x2="80" y2="6" stroke="black" stroke-width="3"/>
        </svg>
      ''',
      width: 80,
      height: 12,
    ),
    'Capacitor': const _ComponentSpec(
      name: 'Capacitor',
      svg: '''
        <svg viewBox="0 0 100 40">
          <line x1="0" y1="20" x2="35" y2="20" stroke="black" stroke-width="2"/>
          <line x1="35" y1="5" x2="35" y2="35" stroke="black" stroke-width="3"/>
          <line x1="65" y1="5" x2="65" y2="35" stroke="black" stroke-width="3"/>
          <line x1="65" y1="20" x2="100" y2="20" stroke="black" stroke-width="2"/>
        </svg>
      ''',
      width: 100,
      height: 40,
    ),
    'Inductor': const _ComponentSpec(
      name: 'Inductor',
      svg: '''
        <svg viewBox="0 0 100 40">
          <line x1="0" y1="20" x2="25" y2="20" stroke="black" stroke-width="2"/>
          <path d="M25 20 C35 5, 45 5, 55 20 S75 35, 85 20" stroke="black" stroke-width="3" fill="none"/>
          <line x1="85" y1="20" x2="100" y2="20" stroke="black" stroke-width="2"/>
        </svg>
      ''',
      width: 100,
      height: 40,
    ),
    'Fuse': const _ComponentSpec(
      name: 'Fuse',
      svg: '''
        <svg viewBox="0 0 100 50">
          <line x1="0" y1="25" x2="22" y2="25" stroke="black" stroke-width="2"/>
          <path d="M22 25 L40 10 L58 40 L76 25 L100 25" stroke="black" stroke-width="3" fill="none"/>
        </svg>
      ''',
      width: 100,
      height: 50,
    ),
    'LED': const _ComponentSpec(
      name: 'LED',
      svg: '''
        <svg viewBox="0 0 100 50">
          <line x1="0" y1="25" x2="25" y2="25" stroke="black" stroke-width="2"/>
          <polygon points="25,10 55,25 25,40" fill="white" stroke="black" stroke-width="2"/>
          <line x1="55" y1="10" x2="55" y2="40" stroke="black" stroke-width="2"/>
          <line x1="55" y1="25" x2="100" y2="25" stroke="black" stroke-width="2"/>
        </svg>
      ''',
      width: 100,
      height: 50,
    ),
    'AND': const _ComponentSpec(
      name: 'AND',
      svg: '''
        <svg viewBox="0 0 90 60">
          <path d="M15 10 H40 Q65 10 65 30 Q65 50 40 50 H15 Z" fill="white" stroke="black" stroke-width="2"/>
          <path d="M65 30 H90" stroke="black" stroke-width="2"/>
          <path d="M0 18 H15" stroke="black" stroke-width="2"/>
          <path d="M0 42 H15" stroke="black" stroke-width="2"/>
        </svg>
      ''',
      width: 90,
      height: 60,
    ),
    'OR': const _ComponentSpec(
      name: 'OR',
      svg: '''
        <svg viewBox="0 0 90 60">
          <path d="M15 10 Q40 10 55 30 Q40 50 15 50 Q25 30 15 10 Z" fill="white" stroke="black" stroke-width="2"/>
          <path d="M55 30 Q75 20 90 30 Q75 40 55 30" fill="none" stroke="black" stroke-width="2"/>
          <path d="M0 18 H15" stroke="black" stroke-width="2"/>
          <path d="M0 42 H15" stroke="black" stroke-width="2"/>
          <path d="M65 30 H90" stroke="black" stroke-width="2"/>
        </svg>
      ''',
      width: 90,
      height: 60,
    ),
    'NOT': const _ComponentSpec(
      name: 'NOT',
      svg: '''
        <svg viewBox="0 0 90 60">
          <path d="M15 10 L15 50 L45 30 Z" fill="white" stroke="black" stroke-width="2"/>
          <circle cx="58" cy="30" r="7" fill="white" stroke="black" stroke-width="2"/>
          <path d="M0 18 H15" stroke="black" stroke-width="2"/>
          <path d="M0 42 H15" stroke="black" stroke-width="2"/>
          <path d="M65 30 H90" stroke="black" stroke-width="2"/>
        </svg>
      ''',
      width: 90,
      height: 60,
    ),
    'NAND': const _ComponentSpec(
      name: 'NAND',
      svg: '''
        <svg viewBox="0 0 100 60">
          <path d="M15 10 H40 Q65 10 65 30 Q65 50 40 50 H15 Z" fill="white" stroke="black" stroke-width="2"/>
          <circle cx="76" cy="30" r="7" fill="white" stroke="black" stroke-width="2"/>
          <path d="M0 18 H15" stroke="black" stroke-width="2"/>
          <path d="M0 42 H15" stroke="black" stroke-width="2"/>
          <path d="M83 30 H100" stroke="black" stroke-width="2"/>
        </svg>
      ''',
      width: 100,
      height: 60,
    ),
    'NOR': const _ComponentSpec(
      name: 'NOR',
      svg: '''
        <svg viewBox="0 0 100 60">
          <path d="M15 10 Q40 10 55 30 Q40 50 15 50 Q25 30 15 10 Z" fill="white" stroke="black" stroke-width="2"/>
          <path d="M55 30 Q75 20 90 30 Q75 40 55 30" fill="none" stroke="black" stroke-width="2"/>
          <circle cx="96" cy="30" r="7" fill="white" stroke="black" stroke-width="2"/>
          <path d="M0 18 H15" stroke="black" stroke-width="2"/>
          <path d="M0 42 H15" stroke="black" stroke-width="2"/>
        </svg>
      ''',
      width: 100,
      height: 60,
    ),
    'XOR': const _ComponentSpec(
      name: 'XOR',
      svg: '''
        <svg viewBox="0 0 100 60">
          <path d="M12 10 Q35 10 50 30 Q35 50 12 50 Q22 30 12 10 Z" fill="white" stroke="black" stroke-width="2"/>
          <path d="M50 10 Q73 10 88 30 Q73 50 50 50 Q60 30 50 10" fill="none" stroke="black" stroke-width="2"/>
          <path d="M0 18 H12" stroke="black" stroke-width="2"/>
          <path d="M0 42 H12" stroke="black" stroke-width="2"/>
          <path d="M88 30 H100" stroke="black" stroke-width="2"/>
        </svg>
      ''',
      width: 100,
      height: 60,
    ),
  };

  final List<_CircuitNode> _nodes = [];
  final List<_Connector> _connectors = [];
  String? _selectedNodeId;
  bool _connectMode = false;
  _DraftConnector? _draftConnector;
  Offset? _draftCursor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Circuit Designer'),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'Connect',
            onPressed: () => setState(() => _connectMode = !_connectMode),
            color: _connectMode ? Colors.amber : Colors.white,
          ),
          IconButton(
            icon: const Icon(Icons.rotate_right),
            tooltip: 'Rotate selected symbol',
            onPressed: _rotateSelectedNode,
          ),
          IconButton(
            icon: const Icon(Icons.alt_route),
            tooltip: 'Turn selected connector',
            onPressed: _toggleSelectedConnectorBend,
          ),
          TextButton(
            onPressed: _insertDiagram,
            child: const Text('Insert', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            color: Colors.grey.shade100,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _components.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => _addNode(entry.key),
                      child: Container(
                        width: 88,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          children: [
                            SizedBox(
                              width: 48,
                              height: 36,
                              child: SvgPicture.string(entry.value.svg),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              entry.key,
                              style: const TextStyle(fontSize: 10),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Expanded(
            child: Container(
              key: _canvasKey,
              color: Colors.grey.shade50,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerMove: (event) {
                  if (_draftConnector == null) return;
                  final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
                  if (box == null) return;
                  setState(() {
                    _draftCursor = box.globalToLocal(event.position);
                  });
                },
                onPointerUp: (event) {
                  if (_draftConnector == null) return;
                  final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
                  if (box == null) return;
                  final point = box.globalToLocal(event.position);
                  final target = _findEndpointAtPoint(point);
                  if (target != null && target.nodeId != _draftConnector!.nodeId) {
                    setState(() {
                      _connectors.add(_Connector(
                        id: 'connector_${DateTime.now().microsecondsSinceEpoch}',
                        fromId: _draftConnector!.nodeId,
                        toId: target.nodeId,
                        fromSide: _draftConnector!.side,
                        toSide: target.side,
                      ));
                    });
                  }
                  setState(() {
                    _draftConnector = null;
                    _draftCursor = null;
                  });
                },
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _ConnectorPainter(
                          _nodes,
                          _connectors,
                          _draftConnector,
                          _draftCursor,
                        ),
                      ),
                    ),
                    ..._nodes.map((node) => Positioned(
                          left: node.x,
                          top: node.y,
                          child: GestureDetector(
                            onPanUpdate: (details) {
                              setState(() {
                                node.x = (node.x + details.delta.dx).clamp(0.0, MediaQuery.of(context).size.width - node.width - 20);
                                node.y = (node.y + details.delta.dy).clamp(0.0, MediaQuery.of(context).size.height - node.height - 120);
                              });
                            },
                            onTap: () {
                              setState(() => _selectedNodeId = node.id);
                            },
                            child: Container(
                              width: node.width,
                              height: node.height,
                              clipBehavior: Clip.none,
                              decoration: BoxDecoration(
                                border: _selectedNodeId == node.id
                                    ? Border.all(color: const Color(0xFF00897B), width: 2)
                                    : null,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Stack(
                                children: [
                                  Center(
                                    child: Transform.rotate(
                                      angle: node.rotation,
                                      alignment: Alignment.center,
                                      child: SvgPicture.string(
                                        node.svg,
                                        width: node.width,
                                        height: node.height,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                  if (_connectMode)
                                    ...[
                                      _buildEndpointHandle(
                                        node,
                                        'left',
                                      ),
                                      _buildEndpointHandle(
                                        node,
                                        'right',
                                      ),
                                    ],
                                ],
                              ),
                            ),
                          ),
                        )),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _addNode(String key) {
    final spec = _components[key]!;
    final id = '${key}_${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _nodes.add(_CircuitNode(
        id: id,
        keyName: key,
        svg: spec.svg,
        width: spec.width.toDouble(),
        height: spec.height.toDouble(),
        x: 40 + (_nodes.length * 20),
        y: 40 + (_nodes.length * 12),
        rotation: 0,
      ));
    });
  }

  Widget _buildEndpointHandle(
    _CircuitNode node,
    String side,
  ) {
    final position = _endpointPoint(node, side);
    final localX = position.dx - node.x;
    final localY = position.dy - node.y;

    return Positioned(
      left: localX - 6,
      top: localY - 6,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => _startDraft(node.id, side),
        onPanUpdate: (details) {
  if (_draftConnector == null || _draftConnector!.nodeId != node.id) {
    _startDraft(node.id, side);
  }
  final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
  if (box != null) {
    setState(() {
      _lastGlobalPointerPosition = details.globalPosition; // ← Add this
      _draftCursor = box.globalToLocal(details.globalPosition);
    });
  }
},
        onPanEnd: (_) {
          final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
          if (box == null) return;
          final point = box.globalToLocal(_lastGlobalPointerPosition ?? Offset.zero);
          final target = _findEndpointAtPoint(point);
          if (target != null && target.nodeId != node.id) {
            setState(() {
              _connectors.add(_Connector(
                id: 'connector_${DateTime.now().microsecondsSinceEpoch}',
                fromId: node.id,
                toId: target.nodeId,
                fromSide: side,
                toSide: target.side,
              ));
            });
          }
          setState(() {
            _draftConnector = null;
            _draftCursor = null;
          });
        },
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFF00897B), width: 1.5),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  void _startDraft(String nodeId, String side) {
    setState(() {
      _selectedNodeId = nodeId;
      _draftConnector = _DraftConnector(nodeId: nodeId, side: side);
      _draftCursor = _endpointPoint(
        _nodes.firstWhere((n) => n.id == nodeId),
        side,
      );
    });
  }

  _EndpointHit? _findEndpointAtPoint(Offset point) {
    for (final node in _nodes) {
      for (final side in const ['left', 'right']) {
        final endpoint = _endpointPoint(node, side);
        if ((point.dx - endpoint.dx).abs() <= 14 &&
            (point.dy - endpoint.dy).abs() <= 14) {
          return _EndpointHit(nodeId: node.id, side: side);
        }
      }
    }
    return null;
  }

  void _rotateSelectedNode() {
    if (_selectedNodeId == null) return;
    final node = _nodes.firstWhere((n) => n.id == _selectedNodeId);
    setState(() {
      node.rotation = (node.rotation + (math.pi / 2)) % (2 * math.pi);
    });
  }

  void _toggleSelectedConnectorBend() {
    // The endpoint-based connector flow now routes automatically.
  }

  void _insertDiagram() {
    final svg = _buildSvg();
    widget.onInsert(svg);
  }

  String _buildSvg() {
  if (_nodes.isEmpty) return '';
  
  // Calculate bounds of all components
  double minX = double.infinity, minY = double.infinity;
  double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
  
  for (final node in _nodes) {
    minX = math.min(minX, node.x);
    minY = math.min(minY, node.y);
    maxX = math.max(maxX, node.x + node.width);
    maxY = math.max(maxY, node.y + node.height);
  }
  
  // Include connector endpoints in bounds
  for (final connector in _connectors) {
    try {
      final fromIndex = _nodes.indexWhere((n) => n.id == connector.fromId);
      final toIndex = _nodes.indexWhere((n) => n.id == connector.toId);
      if (fromIndex != -1 && toIndex != -1) {
        final start = _endpointPoint(_nodes[fromIndex], connector.fromSide);
        final end = _endpointPoint(_nodes[toIndex], connector.toSide);
        minX = math.min(minX, math.min(start.dx, end.dx));
        minY = math.min(minY, math.min(start.dy, end.dy));
        maxX = math.max(maxX, math.max(start.dx, end.dx));
        maxY = math.max(maxY, math.max(start.dy, end.dy));
      }
    } catch (e) {
      print('Error calculating connector bounds: $e');
    }
  }
  
  // Add padding
  const padding = 20.0;
  minX -= padding;
  minY -= padding;
  maxX += padding;
  maxY += padding;
  
  final width = maxX - minX;
  final height = maxY - minY;
  
  // Start SVG
  final buffer = StringBuffer();
  buffer.write('<svg xmlns="http://www.w3.org/2000/svg" ');
  buffer.write('viewBox="${minX.toInt()} ${minY.toInt()} ${width.toInt()} ${height.toInt()}">');

  // Draw connectors FIRST (behind components)
  print('Drawing ${_connectors.length} connectors');
  for (final connector in _connectors) {
    try {
      final fromIndex = _nodes.indexWhere((n) => n.id == connector.fromId);
      final toIndex = _nodes.indexWhere((n) => n.id == connector.toId);
      
      if (fromIndex == -1 || toIndex == -1) {
        print('Connector references missing nodes: from=$fromIndex, to=$toIndex');
        continue;
      }
      
      final start = _endpointPoint(_nodes[fromIndex], connector.fromSide);
      final end = _endpointPoint(_nodes[toIndex], connector.toSide);
      
      // Draw with bright red and thick stroke for visibility
      buffer.write(
        '<line x1="${start.dx.toInt()}" y1="${start.dy.toInt()}" '
        'x2="${end.dx.toInt()}" y2="${end.dy.toInt()}" '
        'stroke="black" stroke-width="3" stroke-linecap="round"/>'
      );
      
      print('Connector: (${start.dx.toInt()},${start.dy.toInt()}) -> (${end.dx.toInt()},${end.dy.toInt()})');
    } catch (e) {
      print('Error drawing connector: $e');
    }
  }

  // Draw components
  for (final node in _nodes) {
    final body = _stripSvgWrapper(node.svg);
    final degrees = node.rotation * 180 / math.pi;
    buffer.write(
      '<g transform="translate(${node.x.toInt()}, ${node.y.toInt()}) '
      'rotate(${degrees.toStringAsFixed(0)} ${node.width/2} ${node.height/2})">'
      '$body'
      '</g>'
    );
  }

  buffer.write('</svg>');
  
  final svgString = buffer.toString();
  print('Final SVG length: ${svgString.length}');
  
  return svgString;
}
  Offset _endpointPoint(_CircuitNode node, String side) {
  // Center of the node
  final centerX = node.x + node.width / 2;
  final centerY = node.y + node.height / 2;
  
  // Local position relative to center (before rotation)
  double localX, localY;
  
  if (side == 'left') {
    localX = -node.width / 2;
    localY = 0;
  } else if (side == 'right') {
    localX = node.width / 2;
    localY = 0;
  } else if (side == 'top') {
    localX = 0;
    localY = -node.height / 2;
  } else if (side == 'bottom') {
    localX = 0;
    localY = node.height / 2;
  } else {
    // Default to right side
    localX = node.width / 2;
    localY = 0;
  }
  
  // Apply rotation
  final angle = node.rotation;
  final cos = math.cos(angle);
  final sin = math.sin(angle);
  
  final rotatedX = localX * cos - localY * sin;
  final rotatedY = localX * sin + localY * cos;
  
  return Offset(centerX + rotatedX, centerY + rotatedY);
}
  List<Offset> _routePoints(Offset start, Offset end) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    if (dx.abs() < 1 || dy.abs() < 1) {
      return [start, end];
    }
    return [
      start,
      Offset(start.dx, end.dy),
      end,
    ];
  }

  String _stripSvgWrapper(String svg) {
  // Only remove the outer svg tags, keeping everything inside
  String cleaned = svg
    .replaceFirst(RegExp(r'<svg[^>]*>'), '')
    .replaceFirst(RegExp(r'</svg>\s*$'), '')
    .trim();
  
  return cleaned;
}
}

class _CircuitNode {
  final String id;
  final String keyName;
  final String svg;
  final double width;
  final double height;
  double x;
  double y;
  double rotation;

  _CircuitNode({
    required this.id,
    required this.keyName,
    required this.svg,
    required this.width,
    required this.height,
    required this.x,
    required this.y,
    required this.rotation,
  });
}

class _Connector {
  final String id;
  final String fromId;
  final String toId;
  final String fromSide;
  final String toSide;

  _Connector({
    required this.id,
    required this.fromId,
    required this.toId,
    required this.fromSide,
    required this.toSide,
  });
}

class _DraftConnector {
  final String nodeId;
  final String side;

  const _DraftConnector({required this.nodeId, required this.side});
}

class _EndpointHit {
  final String nodeId;
  final String side;

  const _EndpointHit({required this.nodeId, required this.side});
}

class _ComponentSpec {
  final String name;
  final String svg;
  final int width;
  final int height;

  const _ComponentSpec({
    required this.name,
    required this.svg,
    required this.width,
    required this.height,
  });
}

class _ConnectorPainter extends CustomPainter {
  final List<_CircuitNode> nodes;
  final List<_Connector> connectors;
  final _DraftConnector? draftConnector;
  final Offset? draftCursor;

  _ConnectorPainter(
    this.nodes,
    this.connectors,
    this.draftConnector,
    this.draftCursor,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black54
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (final connector in connectors) {
      final fromIndex = nodes.indexWhere((n) => n.id == connector.fromId);
      final toIndex = nodes.indexWhere((n) => n.id == connector.toId);
      if (fromIndex == -1 || toIndex == -1) continue;

      final start = _endpointPoint(nodes[fromIndex], connector.fromSide);
      final end = _endpointPoint(nodes[toIndex], connector.toSide);
      final route = _routePoints(start, end);
      if (route.length == 2) {
        canvas.drawLine(route[0], route[1], paint);
      } else {
        final path = Path()
          ..moveTo(route[0].dx, route[0].dy)
          ..lineTo(route[1].dx, route[1].dy)
          ..lineTo(route[2].dx, route[2].dy);
        canvas.drawPath(path, paint);
      }
    }

    if (draftConnector != null && draftCursor != null) {
      final startIndex = nodes.indexWhere((n) => n.id == draftConnector!.nodeId);
      if (startIndex != -1) {
        final start = _endpointPoint(nodes[startIndex], draftConnector!.side);
        final route = _routePoints(start, draftCursor!);
        if (route.length == 2) {
          canvas.drawLine(route[0], route[1], paint..color = Colors.deepOrange);
        } else {
          final path = Path()
            ..moveTo(route[0].dx, route[0].dy)
            ..lineTo(route[1].dx, route[1].dy)
            ..lineTo(route[2].dx, route[2].dy);
          canvas.drawPath(path, paint..color = Colors.deepOrange);
        }
      }
    }
  }

  static Offset _endpointPoint(_CircuitNode node, String side) {
    final centerX = node.x + node.width / 2;
    final centerY = node.y + node.height / 2;
    final localX = side == 'left' ? -node.width / 2 : node.width / 2;
    final localY = 0.0;
    final angle = node.rotation;
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    final rotatedX = localX * cos - localY * sin;
    final rotatedY = localX * sin + localY * cos;
    return Offset(centerX + rotatedX, centerY + rotatedY);
  }

  static List<Offset> _routePoints(Offset start, Offset end) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    if (dx.abs() < 1 || dy.abs() < 1) {
      return [start, end];
    }
    return [
      start,
      Offset(start.dx, end.dy),
      end,
    ];
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
