import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scoring_nidra/src/regional_csv.dart';

void main() {
  test('parses quoted regional CSV values', () {
    final rows = parseCsvTable('Chan,Subjname\nCentral,"Subject, 01"\n');
    expect(rows.single['Chan'], 'Central');
    expect(rows.single['Subjname'], 'Subject, 01');
  });

  test('compiles multiple regional outputs with source provenance', () async {
    final directory = await Directory.systemTemp.createTemp('analyse_master_');
    final first = await File(
      '${directory.path}/first.csv',
    ).writeAsString('Chan,N2_ACW\nCentral,0.12\n');
    final second = await File(
      '${directory.path}/second.csv',
    ).writeAsString('Chan,N2_ACW\nFrontal,0.18\n');

    final compiled = await compileRegionalCsvFiles([first.path, second.path]);

    expect(compiled, contains('source_file,source_path,Chan,N2_ACW'));
    expect(compiled, contains('first.csv'));
    expect(compiled, contains('Frontal,0.18'));
  });
}
