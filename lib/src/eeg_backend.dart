import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';

import 'models.dart';

typedef _LoadViewportNative =
    Pointer<_NativeViewport> Function(Pointer<Utf8> path);
typedef _LoadViewportDart =
    Pointer<_NativeViewport> Function(Pointer<Utf8> path);
typedef _FreeViewportNative = Void Function(Pointer<_NativeViewport> viewport);
typedef _FreeViewportDart = void Function(Pointer<_NativeViewport> viewport);

final class _NativePoint extends Struct {
  @Float()
  external double x;

  @Float()
  external double y;

  @Int32()
  external int channel;
}

final class _NativeViewport extends Struct {
  @Float()
  external double sampleRateHz;

  @Int32()
  external int epochSeconds;

  @Int32()
  external int channelCount;

  @Int32()
  external int pointCount;

  external Pointer<_NativePoint> points;
}

class EegBackend {
  EegBackend() {
    try {
      final library = DynamicLibrary.open(_libraryName);
      _loadViewport = library
          .lookupFunction<_LoadViewportNative, _LoadViewportDart>(
            'sleep_eeg_load_viewport',
          );
      _freeViewport = library
          .lookupFunction<_FreeViewportNative, _FreeViewportDart>(
            'sleep_eeg_free_viewport',
          );
      isNativeAvailable = true;
    } on Object {
      isNativeAvailable = false;
    }
  }

  late final bool isNativeAvailable;
  _LoadViewportDart? _loadViewport;
  _FreeViewportDart? _freeViewport;

  String get _libraryName {
    if (Platform.isMacOS) {
      return 'librust_sleep_eeg.dylib';
    }
    if (Platform.isWindows) {
      return 'rust_sleep_eeg.dll';
    }
    return 'librust_sleep_eeg.so';
  }

  EegViewport loadFileViewport(String path) {
    if (!isNativeAvailable) {
      return loadDemoViewport();
    }

    final pathPointer = path.toNativeUtf8();
    final viewportPointer = _loadViewport!(pathPointer);
    calloc.free(pathPointer);

    if (viewportPointer == nullptr) {
      return loadDemoViewport();
    }

    final viewport = _fromNative(viewportPointer.ref);
    _freeViewport!(viewportPointer);
    return viewport;
  }

  EegViewport loadDemoViewport() {
    const channels = ['F3-M2', 'C3-M2', 'O1-M2', 'EOG-L', 'EMG'];
    const samplesPerChannel = 1800;
    final channelHeight = 1.0 / channels.length;
    final points = <DisplayPoint>[];

    for (var channel = 0; channel < channels.length; channel++) {
      final baseline = channelHeight * (channel + 0.5);
      final frequency = 2.0 + channel * 0.8;
      for (var index = 0; index < samplesPerChannel; index++) {
        final t = index / (samplesPerChannel - 1);
        final slowWave = math.sin(t * math.pi * 2 * frequency);
        final spindle = math.sin(t * math.pi * 2 * 13.5) * 0.18;
        final drift = math.sin(t * math.pi * 2 * 0.18 + channel) * 0.08;
        points.add(
          DisplayPoint(
            x: t,
            y: baseline + (slowWave * 0.10 + spindle + drift) * channelHeight,
            channel: channel,
          ),
        );
      }
    }

    return EegViewport(
      sampleRateHz: 256,
      epochSeconds: 30,
      channelLabels: channels,
      points: points,
      stages: const [
        SleepStage.wake,
        SleepStage.n1,
        SleepStage.n2,
        SleepStage.n2,
        SleepStage.n3,
        SleepStage.n3,
        SleepStage.n2,
        SleepStage.rem,
        SleepStage.rem,
        SleepStage.wake,
      ],
      currentEpoch: 3,
    );
  }

  EegViewport _fromNative(_NativeViewport native) {
    final points = <DisplayPoint>[];
    for (var index = 0; index < native.pointCount; index++) {
      final point = (native.points + index).ref;
      points.add(DisplayPoint(x: point.x, y: point.y, channel: point.channel));
    }

    return EegViewport(
      sampleRateHz: native.sampleRateHz,
      epochSeconds: native.epochSeconds,
      channelLabels: [
        for (var index = 0; index < native.channelCount; index++)
          'Ch ${index + 1}',
      ],
      points: points,
      stages: const [
        SleepStage.wake,
        SleepStage.n1,
        SleepStage.n2,
        SleepStage.n3,
        SleepStage.rem,
      ],
      currentEpoch: 0,
    );
  }
}
