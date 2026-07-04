import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class GraphPlotter extends StatefulWidget {
  final Function(String graphData) onInsertGraph;

  const GraphPlotter({super.key, required this.onInsertGraph});

  @override
  State<GraphPlotter> createState() => _GraphPlotterState();
}

class _GraphPlotterState extends State<GraphPlotter> {
  final _xValuesController = TextEditingController(text: '0, 1, 2, 3, 4, 5');
  final _yValuesController = TextEditingController(text: '0, 2, 4, 6, 8, 10');
  final _xLabelController = TextEditingController(text: 'x');
  final _yLabelController = TextEditingController(text: 'y');
  final _titleController = TextEditingController(text: 'Graph');
  Color _lineColor = Colors.blue;
  bool _showPoints = true;

  List<FlSpot> _getSpots() {
    final xValues = _xValuesController.text
        .split(',')
        .map((s) => double.tryParse(s.trim()) ?? 0)
        .toList();
    final yValues = _yValuesController.text
        .split(',')
        .map((s) => double.tryParse(s.trim()) ?? 0)
        .toList();

    final length = xValues.length < yValues.length ? xValues.length : yValues.length;
    return List.generate(length, (i) => FlSpot(xValues[i], yValues[i]));
  }

  ({double minX, double maxX, double minY, double maxY}) _getAxisBounds(List<FlSpot> spots) {
    if (spots.isEmpty) {
      return (minX: -1, maxX: 1, minY: -1, maxY: 1);
    }

    final allX = [0.0, ...spots.map((s) => s.x)];
    final allY = [0.0, ...spots.map((s) => s.y)];

    final minX = allX.reduce((a, b) => a < b ? a : b);
    final maxX = allX.reduce((a, b) => a > b ? a : b);
    final minY = allY.reduce((a, b) => a < b ? a : b);
    final maxY = allY.reduce((a, b) => a > b ? a : b);

    final xPad = (maxX - minX).abs() < 1 ? 1.0 : (maxX - minX) * 0.18;
    final yPad = (maxY - minY).abs() < 1 ? 1.0 : (maxY - minY) * 0.18;

    final adjustedMinX = minX - xPad;
    final adjustedMaxX = maxX + xPad;
    final adjustedMinY = minY - yPad;
    final adjustedMaxY = maxY + yPad;

    return (
      minX: adjustedMinX,
      maxX: adjustedMaxX,
      minY: adjustedMinY,
      maxY: adjustedMaxY,
    );
  }

  double _niceInterval(double range) {
    if (range <= 0) return 1;

    final raw = range / 5;
    final exponent = raw == 0 ? 0 : math.log(raw) ~/ math.ln10;
    final magnitude = math.pow(10, exponent).toDouble();
    final normalized = raw / magnitude;

    final nice = normalized <= 1
        ? 1
        : normalized <= 2
            ? 2
            : normalized <= 5
                ? 5
                : 10;

    return nice * magnitude;
  }

  String _generateGraphJson() {
    final spots = _getSpots();
    final data = spots.map((s) => '${s.x},${s.y}').join(';');
    return 'GRAPH:${_titleController.text}:${_xLabelController.text}:${_yLabelController.text}:${_lineColor.toARGB32().toRadixString(16)}:$data';
  }

  @override
  Widget build(BuildContext context) {
    final spots = _getSpots();
    final bounds = _getAxisBounds(spots);
    final xRange = bounds.maxX - bounds.minX;
    final yRange = bounds.maxY - bounds.minY;
    final xInterval = _niceInterval(xRange);
    final yInterval = _niceInterval(yRange);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Plot Graph',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1A237E))),
            const SizedBox(height: 12),

            // Live graph preview
            Container(
              height: 320,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              padding: const EdgeInsets.only(right: 48, top: 24, bottom: 24, left: 10),
              child: spots.length >= 2
                  ? LineChart(
                      LineChartData(
                        lineTouchData: LineTouchData(
                          enabled: true,
                          handleBuiltInTouches: true,
                          touchTooltipData: LineTouchTooltipData(
                            tooltipRoundedRadius: 8,
                            tooltipPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            tooltipMargin: 8,
                            getTooltipItems: (touchedSpots) {
                              return touchedSpots.map((spot) {
                                return LineTooltipItem(
                                  '(${spot.x.toStringAsFixed(2)}, ${spot.y.toStringAsFixed(2)})',
                                  const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                );
                              }).toList();
                            },
                          ),
                        ),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: true,
                          drawHorizontalLine: true,
                          getDrawingHorizontalLine: (value) => FlLine(
                            color: Colors.grey.shade200,
                            strokeWidth: 0.5,
                          ),
                          getDrawingVerticalLine: (value) => FlLine(
                            color: Colors.grey.shade200,
                            strokeWidth: 0.5,
                          ),
                        ),
                        extraLinesData: ExtraLinesData(
                          horizontalLines: [
                            if (bounds.minY <= 0 && bounds.maxY >= 0)
                              HorizontalLine(
                                y: 0,
                                color: Colors.black54,
                                strokeWidth: 1.2,
                                dashArray: [4, 4],
                              ),
                          ],
                          verticalLines: [
                            if (bounds.minX <= 0 && bounds.maxX >= 0)
                              VerticalLine(
                                x: 0,
                                color: Colors.black54,
                                strokeWidth: 1.2,
                                dashArray: [4, 4],
                              ),
                          ],
                        ),
                        titlesData: FlTitlesData(
                          show: true,
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            axisNameWidget: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                _xLabelController.text,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                            axisNameSize: 24,
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 32,
                              interval: xInterval,
                              getTitlesWidget: (value, meta) {
                                final label = value.toStringAsFixed(1);
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    label.endsWith('.0') ? label.substring(0, label.length - 2) : label,
                                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                                  ),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            axisNameWidget: Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                _yLabelController.text,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                            axisNameSize: 24,
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 42,
                              interval: yInterval,
                              getTitlesWidget: (value, meta) {
                                final label = value.toStringAsFixed(1);
                                return Text(
                                  label.endsWith('.0') ? label.substring(0, label.length - 2) : label,
                                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                                );
                              },
                            ),
                          ),
                        ),
                        borderData: FlBorderData(
                          show: true,
                          border: Border(
                            left: BorderSide(color: Colors.black, width: 2),
                            bottom: BorderSide(color: Colors.black, width: 2),
                            right: const BorderSide(color: Colors.transparent),
                            top: const BorderSide(color: Colors.transparent),
                          ),
                        ),
                        minX: bounds.minX,
                        maxX: bounds.maxX,
                        minY: bounds.minY,
                        maxY: bounds.maxY,
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            curveSmoothness: 0.3,
                            color: _lineColor,
                            barWidth: 3,
                            isStrokeCapRound: true,
                            dotData: FlDotData(
                              show: _showPoints,
                              getDotPainter: (spot, percent, barData, index) =>
                                  FlDotCirclePainter(
                                radius: 5,
                                color: Colors.white,
                                strokeWidth: 2,
                                strokeColor: _lineColor,
                              ),
                            ),
                            belowBarData: BarAreaData(
                              show: true,
                              color: _lineColor.withValues(alpha: 0.08),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const Center(child: Text('Enter at least 2 points')),
            ),
            const SizedBox(height: 16),

            // Title
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Graph Title',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),

            // X, Y values
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _xValuesController,
                    decoration: InputDecoration(
                      labelText: 'X values (comma)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _yValuesController,
                    decoration: InputDecoration(
                      labelText: 'Y values (comma)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Axis labels
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _xLabelController,
                    decoration: InputDecoration(
                      labelText: 'X-axis label',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _yLabelController,
                    decoration: InputDecoration(
                      labelText: 'Y-axis label',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Color + Points toggle
            Row(
              children: [
                const Text('Color:', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 6),
                ...[Colors.blue, Colors.red, Colors.green, Colors.orange, Colors.purple].map(
                  (color) => GestureDetector(
                    onTap: () => setState(() => _lineColor = color),
                    child: Container(
                      width: 22, height: 22,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: _lineColor == color
                            ? Border.all(color: Colors.black, width: 2)
                            : null,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                const Text('Points', style: TextStyle(fontSize: 12)),
                Switch(
                  value: _showPoints,
                  onChanged: (v) => setState(() => _showPoints = v),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  final graphData = _generateGraphJson();
                  widget.onInsertGraph(graphData);
                },
                icon: const Icon(Icons.insert_chart, size: 18),
                label: const Text('Insert Graph'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A237E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _xValuesController.dispose();
    _yValuesController.dispose();
    _xLabelController.dispose();
    _yLabelController.dispose();
    _titleController.dispose();
    super.dispose();
  }
}