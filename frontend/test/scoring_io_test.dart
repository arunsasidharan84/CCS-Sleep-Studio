import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_sleep_studio/src/models.dart';
import 'package:ccs_sleep_studio/src/scoring_io.dart';

void main() {
  test('loads YASA one-stage-per-line text', () async {
    final file = await _tempScoringFile('yasa', '\nW\nN1\nN2\nN3\nR\n');
    final detection = await detectScoringFormat(file.path);
    final result = await loadScoringFileDirectly(file.path, 'yasa', 5);

    expect(detection.displayName, 'YASA stage list');
    expect(result.stages, [
      SleepStage.wake,
      SleepStage.n1,
      SleepStage.n2,
      SleepStage.n3,
      SleepStage.rem,
    ]);
  });

  test('loads Somnomedics timestamped text', () async {
    final file = await _tempScoringFile('somnomedics', '''
Signal ID: SchlafProfil\\profil
Events list: N3,N2,N1,REM,Wake,Artefact
Rate: 30 s

10:36:00,000; A
10:36:30,000; N2
10:37:00,000; Wake
10:37:30,000; REM
''');
    final detection = await detectScoringFormat(file.path);
    final result = await loadScoringFileDirectly(file.path, 'yasa', 4);

    expect(detection.displayName, 'Somnomedics text');
    expect(result.stages, [
      SleepStage.unknown,
      SleepStage.n2,
      SleepStage.wake,
      SleepStage.rem,
    ]);
  });

  test('loads Polyman text with and without a header', () async {
    for (final includeHeader in [true, false]) {
      final file = await _tempScoringFile('polyman', '''
${includeHeader ? 'Date, Time, Recording onset, Duration, Annotation, Linked channel\n' : ''}20-Sep-2025, 21:44:00, 0, 60, Sleep stage W,
20-Sep-2025, 21:45:00, 60, 30, Sleep stage 1,
20-Sep-2025, 21:45:30, 90, 60, Sleep stage 2,
20-Sep-2025, 21:46:30, 150, 30, Sleep stage R,
''');
      final detection = await detectScoringFormat(file.path);
      final result = await loadScoringFileDirectly(file.path, 'yasa', 6);

      expect(detection.displayName, 'Polyman text');
      expect(result.stages, [
        SleepStage.wake,
        SleepStage.wake,
        SleepStage.n1,
        SleepStage.n2,
        SleepStage.n2,
        SleepStage.rem,
      ]);
    }
  });

  test('loads provided Polyman EDF+ annotations when available', () async {
    final file = File(
      '/Users/arunsasidharan/EEGdata/PooledPSGScoringFormats/'
      'polyman_edfformat.edf',
    );
    if (!file.existsSync()) return;

    final detection = await detectScoringFormat(file.path);
    final result = await loadScoringFileDirectly(file.path, 'edf_anno', 50);
    expect(detection.displayName, 'EDF+ annotations');
    expect(result.stages.take(5), [
      SleepStage.wake,
      SleepStage.n1,
      SleepStage.n1,
      SleepStage.n1,
      SleepStage.n1,
    ]);
  });

  test('distinguishes Sleeptrip and GSSC CSV formats', () async {
    final sleeptrip = await _tempScoringFile(
      'sleeptrip',
      'epoch,start,end,stage\n1,0,30,N2\n',
      extension: 'csv',
    );
    final gssc = await _tempScoringFile(
      'gssc',
      'Epoch,Start,Stage\n1,0,2\n',
      extension: 'csv',
    );

    expect(
      (await detectScoringFormat(sleeptrip.path)).displayName,
      'Sleeptrip CSV',
    );
    expect((await detectScoringFormat(gssc.path)).displayName, 'GSSC CSV');
  });

  test(
    'auto-load backfills probabilities from model scoring sidecar',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ccs_sleep_studio_autoload_',
      );
      final edf = File('${directory.path}/night.edf');
      await edf.writeAsString('placeholder');
      await File('${directory.path}/night_scoring.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert([
          [
            {
              'epoch': 1,
              'start': 0,
              'end': 30,
              'stage': 'N2',
              'digit': -2,
              'confidence': null,
              'channels': [],
              'clean': 1,
              'source': 'human',
            },
          ],
          [],
        ]),
      );
      await File(
        '${directory.path}/night_yasa_sleepgpt_scoring.json',
      ).writeAsString(
        const JsonEncoder.withIndent('  ').convert([
          [
            {
              'epoch': 1,
              'start': 0,
              'end': 30,
              'stage': 'N2',
              'digit': -2,
              'confidence': 0.8,
              'probabilities': {
                'W': 0.05,
                'N1': 0.10,
                'N2': 0.80,
                'N3': 0.03,
                'R': 0.02,
              },
              'channels': [],
              'clean': 1,
              'source': 'yasa_sleepgpt',
            },
          ],
          [],
        ]),
      );

      final result = await tryLoadAutoScoring(edf.path, 1);

      expect(result, isNotNull);
      expect(result!.stages, [SleepStage.n2]);
      expect(result.stagesConfidence, [0.8]);
      expect(result.stageProbabilities.single[SleepStage.n2], 0.8);
    },
  );
}

Future<File> _tempScoringFile(
  String name,
  String content, {
  String extension = 'txt',
}) async {
  final file = File(
    '${Directory.systemTemp.path}/ccs_sleep_studio_${name}_'
    '${DateTime.now().microsecondsSinceEpoch}.$extension',
  );
  return file.writeAsString(content);
}
