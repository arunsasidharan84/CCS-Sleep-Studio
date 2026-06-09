import 'dart:io';
import 'models.dart';

/// Reads all binary data as 16-bit signed integers and reshapes
/// them into 9 channels with 128 Hz sampling rate.
LoadedEeg loadR09(String path) {
  final file = File(path);
  final bytes = file.readAsBytesSync();

  // Read as 16-bit signed integers (little-endian by default for R09)
  final int16list = bytes.buffer.asInt16List();

  const numChannels = 9;
  const sampleRate = 128.0;
  const channelNames = [
    "F3-A2",
    "F4-A1",
    "C3-A2",
    "C4-A1",
    "O1-A2",
    "O2-A1",
    "EOG1",
    "EOG2",
    "EMG",
  ];

  const mapIndices = [3, 4, 5, 6, 7, 8, 1, 2, 0];

  final nSamples = int16list.length;
  final nFrames = nSamples ~/ numChannels;

  final channelSamples = List.generate(numChannels, (_) => List<double>.filled(nFrames, 0.0));

  for (var c = 0; c < numChannels; c++) {
    final channelIdx = mapIndices[c];
    final samples = channelSamples[c];
    for (var f = 0; f < nFrames; f++) {
      samples[f] = int16list[f * numChannels + channelIdx].toDouble();
    }
  }

  return LoadedEeg(
    sampleRateHz: sampleRate,
    channelLabels: channelNames,
    channelSamples: channelSamples,
    sourceDescription: path,
  );
}
