import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_sleep_studio/src/signal_processing.dart' as sp;

void main() {
  test('Check filter stability and print coefficients', () {
    final sampleRate = 256.0;
    // Create a 10-second signal (2560 samples) of 10Hz sine wave + a DC offset of 50.0
    final signal = List<double>.generate(2560, (i) => 50.0 + 10.0 * math.sin(2 * math.pi * 10.0 * i / sampleRate));

    // Design a highpass filter of cutoff 0.3 Hz, order 4
    final hpSos4 = sp.designCheby2SOS(
      order: 4,
      rs: 60.0,
      cutoff: 0.3,
      sampleRate: sampleRate,
      btype: 'highpass',
    );

    print('Chebyshev 2 SOS sections:');
    for (var i = 0; i < hpSos4.length; i++) {
      print('Section $i: ${hpSos4[i]}');
    }

    // Apply zero-phase filter (filtfilt)
    var output = List<double>.from(signal);
    for (final section in hpSos4) {
      output = _applyBiquadSection(output, section);
    }
    output = output.reversed.toList();
    for (final section in hpSos4) {
      output = _applyBiquadSection(output, section);
    }
    output = output.reversed.toList();

    print('First 10 samples of filtered output: ${output.sublist(0, 10)}');
    print('Last 10 samples of filtered output: ${output.sublist(output.length - 10)}');

    // Check if output is nan or infinity or has flattened/blown up
    for (final x in output) {
      expect(x.isFinite, true);
    }
  });
}

List<double> _applyBiquadSection(List<double> input, sp.BiquadSection c) {
  final out = List<double>.filled(input.length, 0.0, growable: false);
  final x0 = input.first;
  final num = c.b0 + c.b1 + c.b2;
  final den = 1.0 + c.a1 + c.a2;
  final G = den.abs() > 1e-12 ? (num / den) : 0.0;

  double s1 = (G - c.b0) * x0;
  double s2 = (c.b2 - c.a2 * G) * x0;

  for (var i = 0; i < input.length; i++) {
    final x = input[i];
    final y = c.b0 * x + s1;
    out[i] = y;
    s1 = c.b1 * x - c.a1 * y + s2;
    s2 = c.b2 * x - c.a2 * y;
  }
  return out;
}
