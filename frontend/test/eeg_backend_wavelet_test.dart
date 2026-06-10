import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:scoring_nidra/src/eeg_backend.dart';
import 'package:scoring_nidra/src/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders lazy wavelet image for a loaded viewport', () async {
    final backend = EegBackend();
    const sampleRate = 64.0;
    final samples = List<double>.generate((sampleRate * 36).round(), (i) {
      final t = i / sampleRate;
      return 40.0 * math.sin(2.0 * math.pi * 10.0 * t) +
          8.0 * math.sin(2.0 * math.pi * 2.0 * t);
    });
    final config = AppConfig.defaultsForChannels(const [
      'C3-M2',
    ], sampleRateHz: sampleRate)..tfFreqMax = 30.0;
    final raw = LoadedEeg(
      sampleRateHz: sampleRate,
      channelLabels: const ['C3-M2'],
      channelSamples: [samples],
      sourceDescription: 'synthetic',
    );

    final eeg = await backend.computeNightProducts(raw, config);
    final viewport = await backend.viewportFromEeg(
      eeg,
      currentEpoch: 0,
      config: config,
      includeTimeFrequency: false,
    );
    final refreshed = await backend.refreshTimeFrequencyForEpoch(
      viewport,
      eeg,
      config: config,
    );

    expect(refreshed.tfPower, isNotEmpty);
    expect(refreshed.tfPower.first, isNotEmpty);
    expect(refreshed.tfImage, isNotNull);
  });

  test('uses configured channels and display limits', () async {
    final backend = EegBackend();
    const sampleRate = 512.0;
    final sampleCount = (sampleRate * 36).round();
    final channels = [
      List<double>.generate(sampleCount, (i) {
        final t = i / sampleRate;
        return math.sin(2.0 * math.pi * 2.0 * t);
      }),
      List<double>.generate(sampleCount, (i) {
        final t = i / sampleRate;
        return math.sin(2.0 * math.pi * 18.0 * t);
      }),
    ];
    final config =
        AppConfig.defaultsForChannels(const [
            'C3-M2',
            'O1-M2',
          ], sampleRateHz: sampleRate)
          ..spectrogramChannelIndex = 1
          ..spectrogramFreqMin = 5.0
          ..spectrogramFreqMax = 25.0
          ..spectrogramPowerMin = -2.0
          ..spectrogramPowerMax = 2.0
          ..tfChannelIndex = 1
          ..tfFreqMin = 6.0
          ..tfFreqMax = 30.0;
    final raw = LoadedEeg(
      sampleRateHz: sampleRate,
      channelLabels: const ['C3-M2', 'O1-M2'],
      channelSamples: channels,
      sourceDescription: 'synthetic',
    );

    final eeg = await backend.computeNightProducts(raw, config);
    final viewport = await backend.viewportFromEeg(
      eeg,
      currentEpoch: 0,
      config: config,
      includeTimeFrequency: false,
    );
    final refreshed = await backend.refreshTimeFrequencyForEpoch(
      viewport,
      eeg,
      config: config,
    );

    expect(eeg.spectrogramChannelIndex, 1);
    expect(viewport.spectrogramChannelIndex, 1);
    expect(viewport.spectrogramFreqMin, 5.0);
    expect(viewport.spectrogramFreqMax, 25.0);
    expect(viewport.spectrogramPowerMin, -2.0);
    expect(viewport.spectrogramPowerMax, 2.0);
    expect(refreshed.tfChannelIndex, 1);
    expect(refreshed.tfFreqs.first, closeTo(6.0, 0.01));
    expect(refreshed.tfFreqs.last, closeTo(30.0, 0.01));
    expect(refreshed.tfPower, isNotEmpty);
  });
}
