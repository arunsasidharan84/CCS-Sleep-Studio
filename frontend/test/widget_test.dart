import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:scoring_nidra/src/app.dart';
import 'package:scoring_nidra/src/detection_dialogs.dart';

void main() {
  testWidgets('renders the sleep EEG viewer shell', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'ScoringNidra',
      packageName: 'scoring_nidra',
      version: '1.1.3',
      buildNumber: '9',
      buildSignature: '',
    );
    await tester.pumpWidget(const ScoringNidraApp());
    await tester.pump();

    expect(find.text('Jump to epoch:'), findsOneWidget);
    expect(find.textContaining('Ready'), findsOneWidget);
    expect(find.text('ScoringNidra v1.1.3 (build 9)'), findsOneWidget);
  });

  testWidgets('batch channel fields allow complete deletion and replacement', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'ScoringNidra',
      packageName: 'scoring_nidra',
      version: '1.1.8',
      buildNumber: '14',
      buildSignature: '',
    );
    await tester.pumpWidget(const ScoringNidraApp());
    await tester.pump();
    await tester.tap(find.text('Batch'));
    await tester.pumpAndSettle();

    final eegField = find.byKey(const Key('batch-autoscore-eeg-channels'));
    expect(eegField, findsOneWidget);
    await tester.enterText(eegField, 'F3,F4');
    await tester.enterText(eegField, '');
    await tester.enterText(eegField, 'C3,C4');

    expect(find.text('C3,C4'), findsOneWidget);
    expect(find.text('F3,F4'), findsNothing);
  });

  testWidgets('interactive autoscoring closes setup before opening progress', (
    tester,
  ) async {
    var callbackCalled = false;
    Map<String, dynamic>? submittedSettings;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (rootContext) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: rootContext,
              builder: (_) => AutoScoringDialog(
                channelLabels: const [
                  'F3:M2',
                  'M1',
                  'E1:M2',
                  'EMG1',
                  'SpO2',
                  'Pulse',
                ],
                onRun: (settings) {
                  callbackCalled = true;
                  submittedSettings = settings;
                  showDialog<void>(
                    context: rootContext,
                    builder: (_) =>
                        const AlertDialog(title: Text('Progress survives')),
                  );
                },
              ),
            ),
            child: const Text('Open autoscoring'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open autoscoring'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run Scoring'));
    await tester.pumpAndSettle();

    expect(callbackCalled, isTrue);
    expect(submittedSettings?['eeg'], ['F3:M2']);
    expect(submittedSettings?['ref'], ['M1']);
    expect(submittedSettings?['eog'], ['E1:M2']);
    expect(submittedSettings?['emg'], ['EMG1']);
    expect(find.text('AutoscoreNidra — Automated Sleep Scoring'), findsNothing);
    expect(find.text('Progress survives'), findsOneWidget);
  });
}
