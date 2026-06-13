import 'dart:math' as math;

import 'models.dart';

List<int> buildPublicationSleepReport({
  required EegViewport viewport,
  required String recordingName,
  required List<Map<String, String>> regionalRows,
}) {
  final report = _PdfDocument();
  final architecture = regionalRows.isEmpty
      ? <String, String>{}
      : regionalRows.first;
  final regions = regionalRows.isEmpty ? <Map<String, String>>[] : regionalRows;

  report.addPage(
    _buildMacrostructurePage(viewport, recordingName, architecture),
  );
  report.addPage(_buildMicrostructurePage(regions));
  report.addPage(_buildAperiodicPage(regions));
  report.addPage(_buildComplexityPage(regions));
  return report.build();
}

String _buildMacrostructurePage(
  EegViewport viewport,
  String recordingName,
  Map<String, String> row,
) {
  final p = _PdfPage();
  _header(p, 'EXECUTIVE SLEEP SUMMARY & CONTINUITY', 'Page 1 of 4');
  p.text(recordingName, 50, 704, bold: true, size: 10);
  p.text(
    '${viewport.epochCount} epochs | ${viewport.epochSeconds}s epoch length',
    50,
    689,
    size: 8,
    color: _slate,
  );

  final cards = <(String, String)>[
    ('TRT', _metric(row, 'TRT', fallback: viewport.totalDurationSeconds / 60)),
    ('TST', _metric(row, 'TST', fallback: _sleepMinutes(viewport))),
    ('WASO', _metric(row, 'WASO')),
    ('SOL', _metric(row, 'SOL')),
    ('Sleep efficiency', '${_metric(row, 'Sleep_efficiency')}%'),
    (
      'Maintenance efficiency',
      '${_metric(row, 'Sleep_Maintenance_Efficiency')}%',
    ),
  ];
  for (var i = 0; i < cards.length; i++) {
    final x = 50.0 + (i % 3) * 172;
    final y = 642.0 - (i ~/ 3) * 53;
    p.rect(x, y, 158, 42, fill: _paleBlue);
    p.text(cards[i].$1, x + 9, y + 27, size: 7.5, color: _slate);
    p.text(cards[i].$2, x + 9, y + 9, bold: true, size: 12, color: _navy);
  }

  p.section('Sleep architecture', 50, 552);
  final stageRows = <(SleepStage, String, String)>[
    (SleepStage.wake, 'Wake', 'W_duration'),
    (SleepStage.n1, 'N1', 'N1_duration'),
    (SleepStage.n2, 'N2', 'N2_duration'),
    (SleepStage.n3, 'N3', 'N3_duration'),
    (SleepStage.rem, 'REM', 'R_duration'),
  ];
  var y = 520.0;
  for (final stageRow in stageRows) {
    final color = _stageColor(stageRow.$1);
    final duration =
        _number(row, stageRow.$3) ??
        viewport.stages.where((stage) => stage == stageRow.$1).length *
            viewport.epochSeconds /
            60;
    final maxDuration = math.max(
      1.0,
      stageRows
          .map((item) => _number(row, item.$3) ?? 0)
          .fold<double>(0, math.max),
    );
    p.text(stageRow.$2, 52, y + 3, bold: true, size: 8);
    p.rect(88, y, 250 * duration / maxDuration, 12, fill: color);
    p.text('${duration.toStringAsFixed(1)} min', 345, y + 2, size: 8);
    y -= 20;
  }

  p.section('Full-night hypnogram', 50, 414);
  _hypnogram(p, viewport, 80, 286, 480, 102);

  p.section('Stage latency dashboard (minutes from recording start)', 50, 254);
  final latencyKeys = <(String, String)>[
    ('Wake onset', 'W_onset'),
    ('N1 latency', 'N1_onset'),
    ('N2 latency', 'N2_onset'),
    ('Deep sleep latency', 'N3_onset'),
    ('REM latency', 'R_onset'),
  ];
  for (var i = 0; i < latencyKeys.length; i++) {
    final x = 50.0 + i * 102;
    p.rect(x, 207, 94, 32, fill: i.isEven ? _paleBlue : _paleGreen);
    p.text(latencyKeys[i].$1, x + 5, 226, size: 6.5, color: _slate);
    p.text(_metric(row, latencyKeys[i].$2), x + 5, 211, bold: true, size: 10);
  }

  p.section('Stage resilience and fragmentation', 50, 178);
  p.text('Stage', 52, 157, bold: true, size: 7);
  p.text('Longest', 126, 157, bold: true, size: 7);
  p.text('Mean streak', 205, 157, bold: true, size: 7);
  p.text('Median streak', 293, 157, bold: true, size: 7);
  p.text('Continuity profile', 392, 157, bold: true, size: 7);
  var tableY = 139.0;
  for (final stage in ['W', 'N1', 'N2', 'N3', 'R']) {
    final longest = _number(row, '${stage}_longest_streak');
    final mean = _number(row, '${stage}_mean_length_of_streak');
    final median = _number(row, '${stage}_median_length_of_streak');
    p.text(stage == 'R' ? 'REM' : stage, 52, tableY, bold: true, size: 7.5);
    p.text(_format(longest), 126, tableY, size: 7.5);
    p.text(_format(mean), 205, tableY, size: 7.5);
    p.text(_format(median), 293, tableY, size: 7.5);
    final continuity = longest == null ? 0.0 : math.min(longest / 120, 1.0);
    p.rect(392, tableY - 2, 145, 8, fill: _lightGray);
    p.rect(392, tableY - 2, 145 * continuity, 8, fill: _teal);
    tableY -= 18;
  }
  _footer(
    p,
    'Macrostructure values are reported in minutes unless otherwise specified.',
  );
  return p.build();
}

String _buildMicrostructurePage(List<Map<String, String>> rows) {
  final p = _PdfPage();
  _header(p, 'THALAMOCORTICAL MICROSTRUCTURE', 'Page 2 of 4');
  p.text(
    'Spindle and slow-wave morphometry with phase-amplitude coupling',
    50,
    704,
    size: 9,
    color: _slate,
  );

  p.section('Regional spindle and slow-wave morphometry', 50, 675);
  const columns = [
    ('Region', 52.0),
    ('Spindles', 122.0),
    ('Density/min', 182.0),
    ('Spindle Hz', 252.0),
    ('Slow waves', 322.0),
    ('SW PTP uV', 390.0),
    ('SW slope', 462.0),
  ];
  for (final column in columns) {
    p.text(column.$1, column.$2, 650, bold: true, size: 7);
  }
  var y = 629.0;
  for (final row in rows.take(8)) {
    p.rect(
      50,
      y - 5,
      512,
      18,
      fill: ((629 - y) ~/ 18).isEven ? _white : _offWhite,
    );
    p.text(row['Chan'] ?? '-', 52, y, bold: true, size: 7.5);
    p.text(_metric(row, 'sp_all_Count', decimals: 0), 122, y, size: 7.5);
    p.text(_metric(row, 'sp_all_density'), 182, y, size: 7.5);
    p.text(_metric(row, 'sp_all_Frequency'), 252, y, size: 7.5);
    p.text(_metric(row, 'sw_all_Count', decimals: 0), 322, y, size: 7.5);
    p.text(_metric(row, 'sw_all_PTP'), 390, y, size: 7.5);
    p.text(_metric(row, 'sw_all_Slope'), 462, y, size: 7.5);
    y -= 18;
  }

  p.section('Phasic spindle-slow wave coupling', 50, 480);
  p.text('Region', 52, 457, bold: true, size: 7);
  p.text('PAC MI', 130, 457, bold: true, size: 7);
  p.text('ndPAC', 195, 457, bold: true, size: 7);
  p.text('Spindle carrier Hz', 260, 457, bold: true, size: 7);
  p.text('SW driver Hz', 365, 457, bold: true, size: 7);
  p.text('Sigma peak phase (rad)', 450, 457, bold: true, size: 7);
  y = 435;
  for (final row in rows.take(8)) {
    p.text(row['Chan'] ?? '-', 52, y, bold: true, size: 7.5);
    p.text(_metric(row, 'pac_all_max_MI', decimals: 4), 130, y, size: 7.5);
    p.text(_metric(row, 'sw_all_ndPAC', decimals: 4), 195, y, size: 7.5);
    p.text(_metric(row, 'pac_all_max_sp'), 260, y, size: 7.5);
    p.text(_metric(row, 'pac_all_max_sw'), 365, y, size: 7.5);
    p.text(_metric(row, 'sw_all_PhaseAtSigmaPeak'), 450, y, size: 7.5);
    y -= 18;
  }

  p.section('Spatial coupling comparison', 50, 315);
  final selected = rows.take(3).toList();
  for (var i = 0; i < selected.length; i++) {
    final row = selected[i];
    final cx = 130.0 + i * 175;
    final cy = 205.0;
    final phase = _number(row, 'sw_all_PhaseAtSigmaPeak') ?? 0;
    final mi = _number(row, 'pac_all_max_MI') ?? 0;
    final ndPac = _number(row, 'sw_all_ndPAC') ?? 0;
    p.circle(cx, cy, 48, stroke: _lightGray);
    p.line(cx - 48, cy, cx + 48, cy, color: _lightGray);
    p.line(cx, cy - 48, cx, cy + 48, color: _lightGray);
    p.line(
      cx,
      cy,
      cx + math.cos(phase) * 43,
      cy + math.sin(phase) * 43,
      color: _purple,
      width: 2,
    );
    p.circle(
      cx,
      cy,
      math.min(38, 8 + mi.abs() * 1000),
      fill: _purple.withAlpha(36),
    );
    p.text(row['Chan'] ?? 'Region', cx - 26, 266, bold: true, size: 9);
    p.text('MI ${mi.toStringAsFixed(4)}', cx - 32, 141, size: 7.5);
    p.text('ndPAC ${ndPac.toStringAsFixed(4)}', cx - 38, 129, size: 7.5);
  }
  p.text(
    'Polar vectors indicate sigma peak phase on the slow-wave cycle. Rightward = 0 rad; upward = pi/2 rad.',
    50,
    92,
    size: 7.5,
    color: _slate,
  );
  _footer(
    p,
    'PAC metrics characterize timing and strength of thalamocortical coordination.',
  );
  return p.build();
}

String _buildAperiodicPage(List<Map<String, String>> rows) {
  final p = _PdfPage();
  _header(p, 'NEURAL EXCITABILITY & APERIODIC TRENDS', 'Page 3 of 4');
  p.text(
    'FOOOF and IRASA parameterization separates periodic peaks from the 1/f background',
    50,
    704,
    size: 9,
    color: _slate,
  );

  p.section('Stage-wise aperiodic trajectory (regional mean)', 50, 675);
  final stages = ['N1', 'N2', 'N3', 'REM'];
  final fooofExponent = [
    for (final stage in stages) _regionalMean(rows, '${stage}_exponent_FOOOF'),
  ];
  final irasaSlope = [
    for (final stage in stages) _regionalMean(rows, '${stage}_slope_Irasa'),
  ];
  _lineChart(
    p,
    x: 70,
    y: 505,
    width: 460,
    height: 130,
    labels: stages,
    series: [
      ('FOOOF exponent', fooofExponent, _blue),
      ('IRASA slope', irasaSlope, _orange),
    ],
  );

  p.section('Aperiodic parameterization and model validation', 50, 470);
  p.text('Stage', 52, 447, bold: true, size: 7);
  p.text('FOOOF offset', 105, 447, bold: true, size: 7);
  p.text('FOOOF exponent', 185, 447, bold: true, size: 7);
  p.text('FOOOF error', 280, 447, bold: true, size: 7);
  p.text('IRASA intercept', 355, 447, bold: true, size: 7);
  p.text('IRASA slope', 445, 447, bold: true, size: 7);
  p.text('IRASA R2 / AUC', 510, 447, bold: true, size: 7);
  var y = 426.0;
  for (final stage in stages) {
    p.text(stage, 52, y, bold: true, size: 7.5);
    p.text(
      _format(_regionalMean(rows, '${stage}_offset_FOOOF')),
      105,
      y,
      size: 7.5,
    );
    p.text(
      _format(_regionalMean(rows, '${stage}_exponent_FOOOF')),
      185,
      y,
      size: 7.5,
    );
    p.text(
      _format(_regionalMean(rows, '${stage}_error_FOOOF')),
      280,
      y,
      size: 7.5,
    );
    p.text(
      _format(_regionalMean(rows, '${stage}_intercept_Irasa')),
      355,
      y,
      size: 7.5,
    );
    p.text(
      _format(_regionalMean(rows, '${stage}_slope_Irasa')),
      445,
      y,
      size: 7.5,
    );
    final r2 = _format(_regionalMean(rows, '${stage}_rsquared_Irasa'));
    final auc = _format(_regionalMean(rows, '${stage}_auc_Irasa'));
    p.text('$r2 / $auc', 510, y, size: 7.5);
    y -= 20;
  }

  p.section(
    'True oscillatory peaks after 1/f removal (regional mean)',
    50,
    330,
  );
  p.text('Stage', 52, 307, bold: true, size: 7);
  p.text('Peak 1 CF', 105, 307, bold: true, size: 7);
  p.text('Peak 1 power', 175, 307, bold: true, size: 7);
  p.text('Peak 1 BW', 255, 307, bold: true, size: 7);
  p.text('Peak 2 CF', 325, 307, bold: true, size: 7);
  p.text('Peak 2 power', 395, 307, bold: true, size: 7);
  p.text('Peak 2 BW', 480, 307, bold: true, size: 7);
  y = 285;
  for (final stage in stages) {
    p.text(stage, 52, y, bold: true, size: 7.5);
    for (var peak = 0; peak < 2; peak++) {
      final x = peak == 0 ? 105.0 : 325.0;
      p.text(
        _format(_regionalMean(rows, '${stage}_cf_${peak}_FOOOF')),
        x,
        y,
        size: 7.5,
      );
      p.text(
        _format(_regionalMean(rows, '${stage}_pw_${peak}_FOOOF')),
        x + 70,
        y,
        size: 7.5,
      );
      p.text(
        _format(_regionalMean(rows, '${stage}_bw_${peak}_FOOOF')),
        x + 150,
        y,
        size: 7.5,
      );
    }
    y -= 20;
  }

  p.section('Interpretive quality flags', 50, 185);
  for (var i = 0; i < stages.length; i++) {
    final stage = stages[i];
    final error = _regionalMean(rows, '${stage}_error_FOOOF');
    final r2 = _regionalMean(rows, '${stage}_rsquared_Irasa');
    final quality = error == null || r2 == null
        ? 'Insufficient data'
        : error < 0.15 && r2 > 0.8
        ? 'High confidence'
        : error < 0.3 && r2 > 0.6
        ? 'Moderate confidence'
        : 'Review fit';
    final color = quality == 'High confidence'
        ? _green
        : quality == 'Moderate confidence'
        ? _orange
        : _red;
    final x = 50.0 + i * 128;
    p.rect(x, 125, 116, 38, fill: color.withAlpha(32));
    p.text(stage, x + 7, 148, bold: true, size: 8, color: color);
    p.text(quality, x + 7, 133, size: 7.5);
  }
  _footer(
    p,
    'Aperiodic parameters should be interpreted alongside fit error and IRASA goodness-of-fit.',
  );
  return p.build();
}

String _buildComplexityPage(List<Map<String, String>> rows) {
  final p = _PdfPage();
  _header(p, 'CORTICAL COMPLEXITY LANDSCAPE', 'Page 4 of 4');
  p.text(
    'Information theory, fractal dynamics, long-range correlations, compression, and temporal memory',
    50,
    704,
    size: 9,
    color: _slate,
  );

  final selectedRows = rows.take(3).toList();
  final stages = ['N1', 'N2', 'N3', 'REM'];
  _heatmap(
    p,
    title: 'Signal entropy profile',
    x: 50,
    y: 650,
    width: 245,
    height: 165,
    rows: selectedRows,
    stages: stages,
    metrics: const [
      'perm_entropy_nonlinear',
      'svd_entropy_nonlinear',
      'sample_entropy_nonlinear',
    ],
  );
  _heatmap(
    p,
    title: 'Fractal dimension and LRTC',
    x: 317,
    y: 650,
    width: 245,
    height: 165,
    rows: selectedRows,
    stages: stages,
    metrics: const [
      'dfa_nonlinear',
      'petrosian_nonlinear',
      'katz_nonlinear',
      'higuchi_nonlinear',
    ],
  );

  p.section(
    'Information compression: global LZc versus stage-wise Lempel-Ziv',
    50,
    442,
  );
  p.text('Region', 52, 419, bold: true, size: 7);
  p.text('Global LZc', 125, 419, bold: true, size: 7);
  for (var i = 0; i < stages.length; i++) {
    p.text(stages[i], 220 + i * 72, 419, bold: true, size: 7);
  }
  var y = 397.0;
  for (final row in selectedRows) {
    p.text(row['Chan'] ?? '-', 52, y, bold: true, size: 7.5);
    p.text(_metric(row, 'LZc', decimals: 3), 125, y, size: 7.5);
    for (var i = 0; i < stages.length; i++) {
      p.text(
        _metric(row, '${stages[i]}_lziv_nonlinear', decimals: 3),
        220 + i * 72,
        y,
        size: 7.5,
      );
    }
    y -= 21;
  }

  p.section('Autocorrelation window: temporal processing memory', 50, 315);
  final acwSeries = <(String, List<double?>, _PdfColor)>[];
  for (var i = 0; i < selectedRows.length; i++) {
    final row = selectedRows[i];
    acwSeries.add((
      row['Chan'] ?? 'Region ${i + 1}',
      [for (final stage in stages) _number(row, '${stage}_ACW')],
      [_blue, _orange, _green][i % 3],
    ));
  }
  _lineChart(
    p,
    x: 70,
    y: 125,
    width: 460,
    height: 145,
    labels: stages,
    series: acwSeries,
  );

  p.text(
    'Higher entropy and fractal metrics indicate less predictable dynamics. DFA summarizes long-range temporal correlations;',
    50,
    94,
    size: 7.5,
    color: _slate,
  );
  p.text(
    'ACW estimates temporal integration persistence.',
    50,
    84,
    size: 7.5,
    color: _slate,
  );
  _footer(
    p,
    'Complexity metrics are descriptive qEEG measures and are not standalone diagnostic biomarkers.',
  );
  return p.build();
}

void _header(_PdfPage p, String title, String page) {
  p.rect(36, 724, 540, 48, fill: _navy);
  p.text(title, 52, 749, bold: true, size: 14, color: _white);
  p.text(
    'ScoringNidra | AnalyseNidra quantitative report',
    52,
    733,
    size: 8,
    color: _sky,
  );
  p.text(page, 520, 733, size: 8, color: _sky);
}

void _footer(_PdfPage p, String note) {
  p.line(50, 58, 562, 58, color: _lightGray);
  p.text(note, 50, 42, size: 6.8, color: _slate);
}

void _hypnogram(
  _PdfPage p,
  EegViewport viewport,
  double x,
  double y,
  double width,
  double height,
) {
  const yMin = -4.0;
  const yMax = 2.5;
  const yRange = yMax - yMin;
  double plotY(double value) => y + height * (value - yMin) / yRange;

  p.rect(x, y, width, height, fill: _offWhite, stroke: _lightGray);
  const labels = <(double, String)>[
    (2.0, 'Event'),
    (1.0, 'W'),
    (0.0, 'REM'),
    (-1.0, 'N1'),
    (-2.0, 'N2'),
    (-3.0, 'N3'),
  ];
  for (final (value, label) in labels) {
    if (label != 'Event') {
      p.line(x, plotY(value), x + width, plotY(value), color: _lightGray);
    }
    final labelY = label == 'Event' ? plotY(value) : plotY(value - 0.5);
    p.text(label, x - 31, labelY - 2, size: 6.5);
  }
  if (viewport.stages.isEmpty) return;

  final epochWidth = width / viewport.stages.length;
  for (var i = 0; i < viewport.stages.length; i++) {
    final stage = viewport.stages[i];
    final stageValue = _stagePlotValue(stage);
    if (stageValue == null || stage == SleepStage.unknown) continue;
    final x0 = x + i * epochWidth;
    final x1 = x0 + math.max(epochWidth, 0.35);
    final bottom = plotY(stageValue - 0.95);
    final top = plotY(stageValue);
    p.rect(x0, bottom, x1 - x0, top - bottom, fill: _stageColor(stage));
    if (i < viewport.stagesUncertain.length && viewport.stagesUncertain[i]) {
      p.rect(x0, bottom, x1 - x0, top - bottom, stroke: _orange);
      p.line(x0, bottom, x1, top, color: _orange, width: 0.7);
    }
  }

  if (viewport.showSwaPlot && viewport.swaPerEpoch.isNotEmpty) {
    final swa = viewport.swaPerEpoch;
    final minSwa = swa.reduce(math.min);
    final maxSwa = swa.reduce(math.max);
    final range = maxSwa - minSwa;
    if (range > 1e-10) {
      final points = <(double, double)>[];
      for (var i = 0; i < viewport.stages.length && i < swa.length; i++) {
        final normalized = (swa[i] - minSwa) / range;
        points.add((x + (i + 0.5) * epochWidth, plotY(5.0 * normalized - 4.0)));
      }
      p.polyline(points, color: _charcoal.withAlpha(145), width: 0.7);
    }
  }

  final fullNightSeconds = viewport.stages.length * 30.0;
  if (fullNightSeconds > 0) {
    for (final event in viewport.scoredEvents) {
      final start = math
          .min(event.startSec, event.endSec)
          .clamp(0.0, fullNightSeconds)
          .toDouble();
      final end = math
          .max(event.startSec, event.endSec)
          .clamp(0.0, fullNightSeconds)
          .toDouble();
      if (end <= start) continue;
      final x1 = x + width * start / fullNightSeconds;
      final x2 = x + width * end / fullNightSeconds;
      p.rect(
        x1,
        plotY(2.0) - 3,
        math.max(1.2, x2 - x1),
        6,
        fill: _eventColor(event.digit),
      );
    }

    final ticks = _hypnogramTimeTicks(fullNightSeconds);
    for (final (label, fraction) in ticks) {
      final tx = x + width * fraction;
      p.line(tx, y, tx, y - 3, color: _slate, width: 0.35);
      p.text(label, tx - 8, y - 12, size: 6.2, color: _slate);
    }
  }

  if (viewport.currentEpoch >= 0 &&
      viewport.currentEpoch < viewport.stages.length) {
    final cursorX = x + width * viewport.currentEpoch / viewport.stages.length;
    p.line(cursorX, y, cursorX, y + height, color: _charcoal, width: 0.9);
  }
}

double? _stagePlotValue(SleepStage stage) => switch (stage) {
  SleepStage.wake => 1.0,
  SleepStage.rem => 0.0,
  SleepStage.n1 => -1.0,
  SleepStage.n2 => -2.0,
  SleepStage.n3 => -3.0,
  SleepStage.inconclusive => 2.0,
  SleepStage.unknown => null,
};

List<(String, double)> _hypnogramTimeTicks(double totalSeconds) {
  const steps = [3600.0, 1800.0, 900.0, 600.0, 300.0, 180.0, 120.0, 60.0];
  var step = 3600.0;
  for (final candidate in steps) {
    if (totalSeconds / candidate >= 2) {
      step = candidate;
      break;
    }
  }
  return [
    for (var seconds = step; seconds < totalSeconds; seconds += step)
      (
        () {
          final hours = (seconds / 3600).floor();
          final minutes = ((seconds % 3600) / 60).round();
          return minutes == 0
              ? '${hours}h'
              : '${hours}h${minutes.toString().padLeft(2, '0')}';
        }(),
        seconds / totalSeconds,
      ),
  ];
}

void _lineChart(
  _PdfPage p, {
  required double x,
  required double y,
  required double width,
  required double height,
  required List<String> labels,
  required List<(String, List<double?>, _PdfColor)> series,
}) {
  final values = series
      .expand((item) => item.$2)
      .whereType<double>()
      .where((value) => value.isFinite)
      .toList();
  final minValue = values.isEmpty ? 0.0 : values.reduce(math.min);
  final maxValue = values.isEmpty ? 1.0 : values.reduce(math.max);
  final range = math.max(maxValue - minValue, 1e-6);
  p.rect(x, y, width, height, stroke: _lightGray);
  for (var i = 0; i < labels.length; i++) {
    final px = labels.length == 1 ? x : x + width * i / (labels.length - 1);
    p.line(px, y, px, y + height, color: _lightGray, width: 0.25);
    p.text(labels[i], px - 8, y - 13, size: 7);
  }
  for (var s = 0; s < series.length; s++) {
    final points = <(double, double)>[];
    for (var i = 0; i < series[s].$2.length; i++) {
      final value = series[s].$2[i];
      if (value == null || !value.isFinite) continue;
      final px = x + width * i / math.max(1, labels.length - 1);
      final py = y + (value - minValue) / range * height;
      points.add((px, py));
      p.circle(px, py, 2.6, fill: series[s].$3);
    }
    p.polyline(points, color: series[s].$3, width: 1.5);
    final legendX = x + s * 145;
    p.line(
      legendX,
      y + height + 14,
      legendX + 18,
      y + height + 14,
      color: series[s].$3,
      width: 2,
    );
    p.text(series[s].$1, legendX + 23, y + height + 11, size: 7);
  }
  p.text(maxValue.toStringAsFixed(2), x - 34, y + height - 3, size: 6.5);
  p.text(minValue.toStringAsFixed(2), x - 34, y - 2, size: 6.5);
}

void _heatmap(
  _PdfPage p, {
  required String title,
  required double x,
  required double y,
  required double width,
  required double height,
  required List<Map<String, String>> rows,
  required List<String> stages,
  required List<String> metrics,
}) {
  p.text(title, x, y, bold: true, size: 9, color: _navy);
  p.text('Stage mean across metrics', x, y - 11, size: 6, color: _slate);
  final cells = <(String, double?)>[];
  for (final row in rows) {
    for (final stage in stages) {
      final values = [
        for (final metric in metrics) _number(row, '${stage}_$metric'),
      ].whereType<double>().toList();
      cells.add((
        '${row['Chan'] ?? '-'} $stage',
        values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length,
      ));
    }
  }
  final numeric = cells.map((cell) => cell.$2).whereType<double>().toList();
  final minValue = numeric.isEmpty ? 0.0 : numeric.reduce(math.min);
  final maxValue = numeric.isEmpty ? 1.0 : numeric.reduce(math.max);
  final range = math.max(maxValue - minValue, 1e-9);
  const labelWidth = 42.0;
  final gridX = x + labelWidth;
  final gridWidth = width - labelWidth;
  final cellWidth = gridWidth / math.max(1, stages.length);
  final cellHeight = (height - 60) / math.max(1, rows.length);
  for (var c = 0; c < stages.length; c++) {
    p.text(
      stages[c],
      gridX + c * cellWidth + cellWidth / 2 - 5,
      y - 24,
      bold: true,
      size: 6.5,
    );
  }
  for (var r = 0; r < rows.length; r++) {
    final rowY = y - 60 - r * cellHeight;
    p.text(rows[r]['Chan'] ?? '-', x, rowY + cellHeight / 2, size: 6.3);
    for (var c = 0; c < stages.length; c++) {
      final value = cells[r * stages.length + c].$2;
      final t = value == null ? 0.0 : (value - minValue) / range;
      final color = _heatColor(t);
      p.rect(
        gridX + c * cellWidth,
        rowY,
        cellWidth - 2,
        cellHeight - 2,
        fill: color,
      );
      p.text(
        value == null ? '-' : value.toStringAsFixed(2),
        gridX + c * cellWidth + 5,
        rowY + cellHeight / 2 - 2,
        size: 5.8,
        color: t > 0.6 ? _white : _charcoal,
      );
    }
  }
}

double _sleepMinutes(EegViewport viewport) {
  return viewport.stages
          .where(
            (stage) =>
                stage == SleepStage.n1 ||
                stage == SleepStage.n2 ||
                stage == SleepStage.n3 ||
                stage == SleepStage.rem,
          )
          .length *
      viewport.epochSeconds /
      60;
}

double? _regionalMean(List<Map<String, String>> rows, String key) {
  final values = rows
      .map((row) => _number(row, key))
      .whereType<double>()
      .where((value) => value.isFinite)
      .toList();
  return values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;
}

double? _number(Map<String, String> row, String key) {
  final raw = row[key]?.trim();
  if (raw == null || raw.isEmpty || raw.toLowerCase() == 'nan') return null;
  final value = double.tryParse(raw);
  return value != null && value.isFinite ? value : null;
}

String _metric(
  Map<String, String> row,
  String key, {
  int decimals = 1,
  double? fallback,
}) {
  final value = _number(row, key) ?? fallback;
  return value == null ? '-' : value.toStringAsFixed(decimals);
}

String _format(double? value, {int decimals = 3}) =>
    value == null ? '-' : value.toStringAsFixed(decimals);

_PdfColor _stageColor(SleepStage stage) => switch (stage) {
  SleepStage.wake => const _PdfColor(0.34, 0.75, 0.55),
  SleepStage.rem => const _PdfColor(0.55, 0.75, 0.34),
  SleepStage.n1 => const _PdfColor(0.67, 0.74, 0.81),
  SleepStage.n2 => const _PdfColor(0.25, 0.36, 0.47),
  SleepStage.n3 => const _PdfColor(0.04, 0.11, 0.17),
  SleepStage.inconclusive => _charcoal,
  SleepStage.unknown => _lightGray,
};

_PdfColor _eventColor(int digit) {
  const colors = [
    _PdfColor(1.00, 0.78, 0.78),
    _PdfColor(0.39, 0.58, 0.93),
    _PdfColor(0.60, 0.98, 0.60),
    _PdfColor(1.00, 1.00, 0.40),
    _PdfColor(0.25, 0.88, 0.82),
    _PdfColor(0.58, 0.40, 0.74),
    _PdfColor(0.55, 0.34, 0.29),
    _PdfColor(0.89, 0.47, 0.76),
    _PdfColor(0.50, 0.50, 0.50),
    _PdfColor(0.74, 0.74, 0.13),
    _PdfColor(1.00, 0.65, 0.00),
    _PdfColor(0.29, 0.00, 0.51),
    _PdfColor(1.00, 0.41, 0.71),
  ];
  return colors[digit.clamp(0, colors.length - 1)];
}

_PdfColor _heatColor(double t) {
  final clamped = t.clamp(0.0, 1.0);
  return _PdfColor(
    0.13 + 0.70 * clamped,
    0.32 + 0.35 * (1 - (clamped - 0.5).abs() * 2),
    0.72 - 0.55 * clamped,
  );
}

const _navy = _PdfColor(0.05, 0.18, 0.31);
const _sky = _PdfColor(0.75, 0.86, 0.96);
const _slate = _PdfColor(0.28, 0.36, 0.45);
const _charcoal = _PdfColor(0.08, 0.10, 0.13);
const _white = _PdfColor(1, 1, 1);
const _offWhite = _PdfColor(0.97, 0.98, 0.99);
const _lightGray = _PdfColor(0.82, 0.85, 0.88);
const _paleBlue = _PdfColor(0.94, 0.97, 1);
const _paleGreen = _PdfColor(0.94, 0.98, 0.95);
const _blue = _PdfColor(0.10, 0.35, 0.65);
const _orange = _PdfColor(0.90, 0.48, 0.12);
const _green = _PdfColor(0.12, 0.58, 0.35);
const _red = _PdfColor(0.78, 0.18, 0.20);
const _purple = _PdfColor(0.48, 0.20, 0.67);
const _teal = _PdfColor(0.10, 0.55, 0.56);

class _PdfColor {
  const _PdfColor(this.r, this.g, this.b, [this.alpha = 255]);

  final double r;
  final double g;
  final double b;
  final int alpha;

  _PdfColor withAlpha(int value) => _PdfColor(r, g, b, value);

  String get fill => '${_blend(r)} ${_blend(g)} ${_blend(b)} rg';
  String get stroke => '${_blend(r)} ${_blend(g)} ${_blend(b)} RG';

  double _blend(double channel) {
    final opacity = alpha / 255;
    return channel * opacity + (1 - opacity);
  }
}

class _PdfPage {
  final List<String> _commands = [];

  void text(
    String text,
    double x,
    double y, {
    bool bold = false,
    double size = 10,
    _PdfColor color = _charcoal,
  }) {
    final font = bold ? '/F2' : '/F1';
    final escaped = text
        .replaceAll('\\', '\\\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)')
        .replaceAll('µ', 'u')
        .replaceAll('κ', 'k')
        .replaceAll('π', 'pi');
    _commands.add('BT ${color.fill} $font $size Tf $x $y Td ($escaped) Tj ET');
  }

  void section(String title, double x, double y) {
    text(title, x, y, bold: true, size: 10.5, color: _navy);
    line(x, y - 5, 562, y - 5, color: _lightGray);
  }

  void rect(
    double x,
    double y,
    double width,
    double height, {
    _PdfColor? fill,
    _PdfColor? stroke,
  }) {
    if (fill != null) {
      _commands.add('${fill.fill} $x $y $width $height re f');
    }
    if (stroke != null) {
      _commands.add('${stroke.stroke} 0.5 w $x $y $width $height re S');
    }
  }

  void line(
    double x1,
    double y1,
    double x2,
    double y2, {
    _PdfColor color = _charcoal,
    double width = 0.5,
  }) {
    _commands.add('${color.stroke} $width w $x1 $y1 m $x2 $y2 l S');
  }

  void circle(
    double cx,
    double cy,
    double radius, {
    _PdfColor? fill,
    _PdfColor? stroke,
  }) {
    const k = 0.5522847498;
    final c = radius * k;
    final path =
        '${cx + radius} $cy m '
        '${cx + radius} ${cy + c} ${cx + c} ${cy + radius} $cx ${cy + radius} c '
        '${cx - c} ${cy + radius} ${cx - radius} ${cy + c} ${cx - radius} $cy c '
        '${cx - radius} ${cy - c} ${cx - c} ${cy - radius} $cx ${cy - radius} c '
        '${cx + c} ${cy - radius} ${cx + radius} ${cy - c} ${cx + radius} $cy c';
    if (fill != null) _commands.add('${fill.fill} $path f');
    if (stroke != null) _commands.add('${stroke.stroke} 0.5 w $path S');
  }

  void polyline(
    List<(double, double)> points, {
    _PdfColor color = _charcoal,
    double width = 0.5,
  }) {
    if (points.length < 2) return;
    final path = StringBuffer('${points.first.$1} ${points.first.$2} m');
    for (final point in points.skip(1)) {
      path.write(' ${point.$1} ${point.$2} l');
    }
    _commands.add('${color.stroke} $width w $path S');
  }

  String build() => _commands.join('\n');
}

class _PdfDocument {
  final List<String> _pages = [];

  void addPage(String page) => _pages.add(page);

  List<int> build() {
    final numPages = _pages.length;
    final font1 = 2 * numPages + 3;
    final font2 = 2 * numPages + 4;
    final kids = List.generate(numPages, (i) => '${2 * i + 3} 0 R').join(' ');
    final objects = <String>[
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Kids [$kids] /Count $numPages >>',
    ];
    for (var i = 0; i < numPages; i++) {
      final content = _pages[i];
      final contentIndex = 2 * i + 4;
      objects.add(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Resources << /Font << /F1 $font1 0 R /F2 $font2 0 R >> >> '
        '/Contents $contentIndex 0 R >>',
      );
      objects.add(
        '<< /Length ${content.length} >>\nstream\n$content\nendstream',
      );
    }
    objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
    objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>');

    final buffer = StringBuffer('%PDF-1.4\n');
    final offsets = <int>[0];
    for (var i = 0; i < objects.length; i++) {
      offsets.add(buffer.length);
      buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
    }
    final xref = buffer.length;
    buffer.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
    for (final offset in offsets.skip(1)) {
      buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    buffer.write(
      'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n',
    );
    return buffer.toString().codeUnits;
  }
}
