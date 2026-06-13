import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scoring_nidra/src/eeg_backend.dart';
import 'package:scoring_nidra/src/models.dart';
import 'package:scoring_nidra/src/publication_sleep_report.dart';
import 'package:scoring_nidra/src/regional_csv.dart';

void main() {
  test('builds a four-page quantitative sleep report', () {
    final viewport = EegBackend().loadDemoViewport().copyWith(
      currentEpoch: 4,
      stages: const [
        SleepStage.wake,
        SleepStage.n1,
        SleepStage.n2,
        SleepStage.n2,
        SleepStage.n3,
        SleepStage.n3,
        SleepStage.rem,
        SleepStage.rem,
      ],
      stagesUncertain: const [
        false,
        true,
        false,
        false,
        false,
        false,
        false,
        false,
      ],
      scoredEvents: const [
        ScoredEvent(
          digit: 0,
          key: 'A',
          label: 'Artifact',
          startSec: 30,
          endSec: 75,
        ),
        ScoredEvent(
          digit: 1,
          key: 'F1',
          label: 'Spindle',
          startSec: 120,
          endSec: 180,
        ),
      ],
    );
    final bytes = buildPublicationSleepReport(
      viewport: viewport,
      recordingName: 'subject.edf',
      regionalRows: [
        {
          'Chan': 'Central',
          'TRT': '480',
          'TST': '410',
          'N2_exponent_FOOOF': '1.4',
          'N2_slope_Irasa': '-1.2',
          'N2_perm_entropy_nonlinear': '0.8',
          'N2_ACW': '0.12',
        },
      ],
    );
    final pdf = latin1.decode(bytes);

    expect(pdf, startsWith('%PDF-1.4'));
    expect(pdf, contains('/Count 4'));
    expect(pdf, contains('THALAMOCORTICAL MICROSTRUCTURE'));
    expect(pdf, contains('CORTICAL COMPLEXITY LANDSCAPE'));
    expect(pdf, contains('(Event)'));
    expect(pdf, contains('0.39 0.58 0.93 rg'));
  });

  test('optionally renders a supplied AnalyseNidra CSV', () {
    final csvPath = Platform.environment['REPORT_CSV'];
    final outputPath = Platform.environment['REPORT_OUT'];
    if (csvPath == null || outputPath == null) {
      return;
    }

    final csv = File(csvPath);
    expect(csv.existsSync(), isTrue);
    final bytes = buildPublicationSleepReport(
      viewport: EegBackend().loadDemoViewport(),
      recordingName: csv.uri.pathSegments.last,
      regionalRows: parseCsvTable(csv.readAsStringSync()),
    );
    File(outputPath).writeAsBytesSync(bytes);

    expect(bytes, isNotEmpty);
  });
}
