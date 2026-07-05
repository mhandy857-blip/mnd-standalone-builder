import 'package:mnd_core/contracts/script_runtime.dart';

class QuestTable implements ScriptTable {
  String name;
  List<String> columns;

  // Classic table rows: index-based access.
  List<Map<String, dynamic>> rows;

  // Key-value storage for script-friendly lookups.
  @override
  Map<String, dynamic> data;

  QuestTable({
    required this.name,
    required this.columns,
    required this.rows,
    this.data = const {},
  });

  factory QuestTable.fromJson(Map<String, dynamic> json) {
    return QuestTable(
      name: json['name'] as String,
      columns: List<String>.from(json['columns'] ?? []),
      rows: (json['rows'] as List<dynamic>? ?? [])
          .map((row) => Map<String, dynamic>.from(row))
          .toList(),
      data: (json['data'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'columns': columns, 'rows': rows, 'data': data};
  }

  void addEmptyRow() {
    final Map<String, dynamic> newRow = {};
    for (final col in columns) {
      newRow[col] = '';
    }
    rows.add(newRow);
  }

  void updateColumns(List<String> newColumns) {
    for (final row in rows) {
      row.removeWhere((key, value) => !newColumns.contains(key));
    }
    for (final col in newColumns) {
      for (final row in rows) {
        row.putIfAbsent(col, () => '');
      }
    }
    columns = newColumns;
  }
}
