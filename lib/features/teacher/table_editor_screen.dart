import 'package:flutter/material.dart';

class TableEditorScreen extends StatefulWidget {
  final void Function(List<List<String>>) onInsertTable;

  const TableEditorScreen({super.key, required this.onInsertTable});

  @override
  State<TableEditorScreen> createState() => _TableEditorScreenState();
}

class _TableEditorScreenState extends State<TableEditorScreen> {
  int _rows = 2;
  int _columns = 2;
  late List<List<TextEditingController>> _controllers;

  @override
  void initState() {
    super.initState();
    _resetControllers();
  }

  void _resetControllers() {
    _controllers = List.generate(
      _rows,
      (_) => List.generate(_columns, (_) => TextEditingController()),
    );
  }

  void _updateGridSize({required int rows, required int columns}) {
    setState(() {
      _rows = rows;
      _columns = columns;
      _resetControllers();
    });
  }

  List<List<String>> _collectTable() {
    return _controllers
        .map((row) => row.map((controller) => controller.text.trim()).toList())
        .toList();
  }

  @override
  void dispose() {
    for (final row in _controllers) {
      for (final controller in row) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Insert Table'),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _rows,
                    decoration: const InputDecoration(labelText: 'Rows'),
                    items: List.generate(6, (index) => index + 1)
                        .map((value) => DropdownMenuItem(value: value, child: Text('$value')))
                        .toList(),
                    onChanged: (value) => value != null
                        ? _updateGridSize(rows: value, columns: _columns)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _columns,
                    decoration: const InputDecoration(labelText: 'Columns'),
                    items: List.generate(6, (index) => index + 1)
                        .map((value) => DropdownMenuItem(value: value, child: Text('$value')))
                        .toList(),
                    onChanged: (value) => value != null
                        ? _updateGridSize(rows: _rows, columns: value)
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Table(
                    border: TableBorder.all(color: Colors.grey.shade300),
                    defaultColumnWidth: const IntrinsicColumnWidth(),
                    children: List.generate(_rows, (rowIndex) {
                      return TableRow(
                        children: List.generate(_columns, (colIndex) {
                          return Padding(
                            padding: const EdgeInsets.all(6),
                            child: SizedBox(
                              width: 120,
                              child: TextField(
                                controller: _controllers[rowIndex][colIndex],
                                decoration: InputDecoration(
                                  hintText: 'Cell ${rowIndex + 1}-${colIndex + 1}',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                          );
                        }),
                      );
                    }),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      widget.onInsertTable(_collectTable());
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.table_chart_outlined),
                    label: const Text('Insert Table'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00897B),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
