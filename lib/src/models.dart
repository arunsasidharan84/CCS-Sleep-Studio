enum SleepStage {
  wake('W', 0),
  n1('N1', 1),
  n2('N2', 2),
  n3('N3', 3),
  rem('REM', 4),
  unknown('?', 5);

  const SleepStage(this.label, this.code);

  final String label;
  final int code;

  static SleepStage fromCode(int code) {
    return SleepStage.values.firstWhere(
      (stage) => stage.code == code,
      orElse: () => SleepStage.unknown,
    );
  }
}

class DisplayPoint {
  const DisplayPoint({required this.x, required this.y, required this.channel});

  final double x;
  final double y;
  final int channel;
}

class EegViewport {
  const EegViewport({
    required this.sampleRateHz,
    required this.epochSeconds,
    required this.channelLabels,
    required this.points,
    required this.stages,
    required this.currentEpoch,
  });

  final double sampleRateHz;
  final int epochSeconds;
  final List<String> channelLabels;
  final List<DisplayPoint> points;
  final List<SleepStage> stages;
  final int currentEpoch;

  int get epochCount => stages.length;

  EegViewport copyWith({List<SleepStage>? stages}) {
    return EegViewport(
      sampleRateHz: sampleRateHz,
      epochSeconds: epochSeconds,
      channelLabels: channelLabels,
      points: points,
      stages: stages ?? this.stages,
      currentEpoch: currentEpoch,
    );
  }
}
