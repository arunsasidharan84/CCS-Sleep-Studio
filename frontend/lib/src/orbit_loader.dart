// lib/src/orbit_loader.dart

import 'dart:convert';
import 'dart:io';
import 'models.dart';

class OrbitLoader {
  LoadedEeg load(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileNotFoundException('File not found: $path');
    }

    final lines = file.readAsLinesSync();
    if (lines.isEmpty) {
      throw const FormatException('Orbit file is empty.');
    }

    // Temporary maps to store values keyed by integer timestamp T.
    // T represents sample index at 250 Hz.
    final Map<int, double> chanA = {};
    final Map<int, double> chanB = {};
    final Map<int, double> chanC = {};
    final Map<int, double> chanD = {};
    final Map<int, double> chanE = {}; // PPG

    bool has4Channels = false;

    for (var lineNo = 0; lineNo < lines.length; lineNo++) {
      final line = lines[lineNo].trim();
      if (line.isEmpty) continue;

      try {
        final decoded = json.decode(line);
        if (decoded is! Map) continue;

        final tVal = decoded['T'];
        if (tVal is! List) continue;

        final List<int> timestamps = tVal.map<int>((e) => (e as num).toInt()).toList();
        final numSamples = timestamps.length;
        if (numSamples == 0) continue;

        // Parse channel A
        final aVal = decoded['A'];
        final List<double> aSamples = _parseList(aVal, numSamples);

        // Parse channel B
        final bVal = decoded['B'];
        final List<double> bSamples = _parseList(bVal, numSamples);

        // Parse channel C (optional 4-channel EEG)
        final cVal = decoded['C'];
        final List<double> cSamples = _parseList(cVal, numSamples);
        if (cVal is List && cVal.length > 1) {
          has4Channels = true;
        }

        // Parse channel D (optional 4-channel EEG)
        final dVal = decoded['D'];
        final List<double> dSamples = _parseList(dVal, numSamples);
        if (dVal is List && dVal.length > 1) {
          has4Channels = true;
        }

        // Parse channel E (PPG)
        final eVal = decoded['E'];
        List<double> eSamples;
        if (eVal is List) {
          eSamples = _parseList(eVal, numSamples);
        } else if (eVal is num) {
          // Repeat scalar PPG value
          eSamples = List<double>.filled(numSamples, eVal.toDouble());
        } else {
          eSamples = List<double>.filled(numSamples, 0.0);
        }

        for (var i = 0; i < numSamples; i++) {
          final t = timestamps[i];
          chanA[t] = aSamples[i];
          chanB[t] = bSamples[i];
          if (cSamples.isNotEmpty) chanC[t] = cSamples[i];
          if (dSamples.isNotEmpty) chanD[t] = dSamples[i];
          chanE[t] = eSamples[i];
        }
      } catch (e) {
        // Ignore malformed lines and continue
        continue;
      }
    }

    if (chanA.isEmpty || chanB.isEmpty) {
      throw const FormatException('Orbit file contains no valid EEG channel data.');
    }

    // Get timestamp range
    final allTimestamps = chanA.keys.toList()..sort();
    final minT = allTimestamps.first;
    final maxT = allTimestamps.last;
    final totalSamples = maxT - minT + 1;

    if (totalSamples <= 0) {
      throw const FormatException('Orbit file contains invalid timestamp range.');
    }

    // Reconstruct continuous arrays of raw values (filled with double.nan where missing)
    final List<double> rawA = List<double>.filled(totalSamples, double.nan);
    final List<double> rawB = List<double>.filled(totalSamples, double.nan);
    final List<double>? rawC = has4Channels ? List<double>.filled(totalSamples, double.nan) : null;
    final List<double>? rawD = has4Channels ? List<double>.filled(totalSamples, double.nan) : null;
    final List<double> rawE = List<double>.filled(totalSamples, double.nan);

    for (var i = 0; i < totalSamples; i++) {
      final t = minT + i;
      rawA[i] = chanA[t] ?? double.nan;
      rawB[i] = chanB[t] ?? double.nan;
      if (has4Channels) {
        rawC![i] = chanC[t] ?? double.nan;
        rawD![i] = chanD[t] ?? double.nan;
      }
      rawE[i] = chanE[t] ?? double.nan;
    }

    // Interpolate channels
    final List<double> interpA = _interpolateChannel(rawA);
    final List<double> interpB = _interpolateChannel(rawB);
    final List<double>? interpC = has4Channels ? _interpolateChannel(rawC!) : null;
    final List<double>? interpD = has4Channels ? _interpolateChannel(rawD!) : null;
    final List<double> interpE = _interpolateChannel(rawE);

    // Apply scaling
    // EEG channels: -0.01 (raw to microvolts)
    // PPG channel: 0.1
    for (var i = 0; i < totalSamples; i++) {
      interpA[i] *= -0.01;
      interpB[i] *= -0.01;
      if (has4Channels) {
        interpC![i] *= -0.01;
        interpD![i] *= -0.01;
      }
      interpE[i] *= 0.1;
    }

    final List<String> channelLabels = has4Channels
        ? ['AF7', 'AF8', 'Ch3', 'Ch4', 'PPG']
        : ['AF7', 'AF8', 'PPG'];

    final List<List<double>> channelSamples = has4Channels
        ? [interpA, interpB, interpC!, interpD!, interpE]
        : [interpA, interpB, interpE];

    final double sampleRate = 250.0;
    final double durationMin = totalSamples / sampleRate / 60.0;

    return LoadedEeg(
      sampleRateHz: sampleRate,
      channelLabels: channelLabels,
      channelSamples: channelSamples,
      sourceDescription:
          '${channelLabels.length} channels, ${sampleRate.toStringAsFixed(1)} Hz, ${durationMin.toStringAsFixed(1)} min (Orbit)',
    );
  }

  List<double> _parseList(dynamic value, int expectedLength) {
    if (value is List) {
      return value.map<double>((e) => (e as num).toDouble()).toList();
    }
    return List<double>.filled(expectedLength, 0.0);
  }

  List<double> _interpolateChannel(List<double> data) {
    final n = data.length;
    final result = List<double>.from(data);

    // Find first non-nan index
    int firstKnown = -1;
    for (var i = 0; i < n; i++) {
      if (!data[i].isNaN) {
        firstKnown = i;
        break;
      }
    }

    if (firstKnown == -1) {
      // All are NaN, fill with zero
      return List<double>.filled(n, 0.0);
    }

    // Fill anything before the first known index with the first known value
    for (var i = 0; i < firstKnown; i++) {
      result[i] = data[firstKnown];
    }

    int lastKnownIdx = firstKnown;
    double lastKnownVal = data[firstKnown];

    int i = firstKnown + 1;
    while (i < n) {
      if (!data[i].isNaN) {
        lastKnownIdx = i;
        lastKnownVal = data[i];
        i++;
      } else {
        // Find next known index
        int nextKnownIdx = -1;
        for (var j = i; j < n; j++) {
          if (!data[j].isNaN) {
            nextKnownIdx = j;
            break;
          }
        }

        if (nextKnownIdx == -1) {
          // No more known values, fill rest with lastKnownVal
          for (var j = i; j < n; j++) {
            result[j] = lastKnownVal;
          }
          break;
        } else {
          // Interpolate between lastKnownIdx and nextKnownIdx
          final double nextKnownVal = data[nextKnownIdx];
          final double step = (nextKnownVal - lastKnownVal) / (nextKnownIdx - lastKnownIdx);
          for (var j = i; j < nextKnownIdx; j++) {
            result[j] = lastKnownVal + step * (j - lastKnownIdx);
          }
          lastKnownIdx = nextKnownIdx;
          lastKnownVal = nextKnownVal;
          i = nextKnownIdx + 1;
        }
      }
    }

    return result;
  }
}

class FileNotFoundException implements Exception {
  final String message;
  FileNotFoundException(this.message);
  @override
  String toString() => message;
}
