import 'dart:convert';
import 'dart:io';

List<String> parseCsvLine(String line) {
  final fields = <String>[];
  final current = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      if (quoted && i + 1 < line.length && line[i + 1] == '"') {
        current.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (char == ',' && !quoted) {
      fields.add(current.toString());
      current.clear();
    } else {
      current.write(char);
    }
  }
  fields.add(current.toString());
  return fields;
}

List<Map<String, String>> parseCsvTable(String source) {
  final lines = const LineSplitter()
      .convert(source)
      .where((line) => line.trim().isNotEmpty)
      .toList();
  if (lines.length < 2) return const [];
  final headers = parseCsvLine(lines.first);
  final rows = <Map<String, String>>[];
  for (final line in lines.skip(1)) {
    final values = parseCsvLine(line);
    rows.add({
      for (var i = 0; i < headers.length; i++)
        headers[i]: i < values.length ? values[i] : '',
    });
  }
  return rows;
}

Future<String> compileRegionalCsvFiles(List<String> paths) async {
  if (paths.isEmpty) {
    throw ArgumentError('Select at least one AnalyseNidra regional CSV file.');
  }
  final headers = <String>['source_file', 'source_path'];
  final rows = <Map<String, String>>[];

  for (final path in paths) {
    final file = File(path);
    final parsed = parseCsvTable(await file.readAsString());
    for (final row in parsed) {
      for (final key in row.keys) {
        if (!headers.contains(key)) headers.add(key);
      }
      rows.add({
        'source_file': file.uri.pathSegments.last,
        'source_path': file.absolute.path,
        ...row,
      });
    }
  }

  final buffer = StringBuffer()..writeln(headers.map(_escapeCsv).join(','));
  for (final row in rows) {
    buffer.writeln(
      headers.map((header) => _escapeCsv(row[header] ?? '')).join(','),
    );
  }
  return buffer.toString();
}

String _escapeCsv(String value) {
  if (!value.contains(RegExp(r'[",\r\n]'))) return value;
  return '"${value.replaceAll('"', '""')}"';
}
