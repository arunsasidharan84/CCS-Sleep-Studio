import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring_nidra/src/signal_processing.dart' as sp;

List<double> applyZeroPhaseSOS(
  List<double> input,
  List<sp.BiquadSection> sos,
) {
  var output = List<double>.from(input);
  for (final section in sos) {
    output = applyBiquadSection(output, section);
  }
  output = output.reversed.toList(growable: false);
  for (final section in sos) {
    output = applyBiquadSection(output, section);
  }
  return output.reversed.toList(growable: false);
}

List<double> applyBiquadSection(List<double> input, sp.BiquadSection c) {
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

void main() {
  test('Test notch filter stability and NaN generation', () {
    final sampleRate = 256.0;
    // Create a signal with some 50Hz noise and DC offset
    final signal = List<double>.generate(1000, (i) {
      final t = i / sampleRate;
      return 100.0 + 5.0 * math.sin(2.0 * math.pi * 50.0 * t);
    });

    try {
      print('Designing notch filter: cutoff=50.0Hz, order=4');
      final sos = sp.designCheby2SOS(
        order: 4,
        rs: 60.0,
        cutoff: 50.0,
        sampleRate: sampleRate,
        btype: 'bandstop',
      );
      print('Coefficients of order 4 Notch:');
      for (final sec in sos) {
        print('  sec: $sec');
      }

      final filtered = applyZeroPhaseSOS(signal, sos);
      final hasNaN = filtered.any((x) => x.isNaN || x.isInfinite);
      double maxVal = 0.0;
      for (final x in filtered) {
        if (x.abs() > maxVal) maxVal = x.abs();
      }
      print('Notch filter: hasNaN=$hasNaN, maxVal=$maxVal');
      expect(hasNaN, isFalse);
      expect(maxVal, lessThan(200.0));
    } catch (e, stack) {
      print('Failed notch filter test: $e');
      print(stack);
      fail('Notch filter failed');
    }
  });
}
