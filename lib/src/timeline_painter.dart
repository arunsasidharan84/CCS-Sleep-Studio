import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';

class TimelinePainter extends CustomPainter {
  const TimelinePainter(this.viewport);

  final EegViewport viewport;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFE6ECEA)
      ..strokeWidth = 1;
    final tracePaint = Paint()
      ..color = const Color(0xFF153F3B)
      ..strokeWidth = 1.15
      ..style = PaintingStyle.stroke;
    final labelPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
    );

    for (var second = 0; second <= 30; second += 5) {
      final x = size.width * second / 30;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    for (var channel = 0; channel < viewport.channelLabels.length; channel++) {
      final y = size.height * (channel + 0.5) / viewport.channelLabels.length;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      labelPainter.text = TextSpan(
        text: viewport.channelLabels[channel],
        style: const TextStyle(
          color: Color(0xFF49635F),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      );
      labelPainter.layout(maxWidth: 90);
      labelPainter.paint(canvas, Offset(10, y - 22));
    }

    final paths = <int, Path>{};
    for (final point in viewport.points) {
      final path = paths.putIfAbsent(point.channel, Path.new);
      final x = point.x.clamp(0.0, 1.0) * size.width;
      final y = point.y.clamp(0.0, 1.0) * size.height;
      if (path.getBounds().isEmpty) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    for (final path in paths.values) {
      canvas.drawPath(path, tracePaint);
    }

    final epochWidth = size.width / math.max(viewport.epochCount, 1);
    final epochPaint = Paint()
      ..color = const Color(0x3324786D)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(
        epochWidth * viewport.currentEpoch,
        0,
        epochWidth,
        size.height,
      ),
      epochPaint,
    );
  }

  @override
  bool shouldRepaint(covariant TimelinePainter oldDelegate) {
    return oldDelegate.viewport != viewport;
  }
}

class HypnogramPainter extends CustomPainter {
  const HypnogramPainter(this.viewport);

  final EegViewport viewport;

  @override
  void paint(Canvas canvas, Size size) {
    final axisPaint = Paint()
      ..color = const Color(0xFFB9C5C2)
      ..strokeWidth = 1;
    final linePaint = Paint()
      ..color = const Color(0xFF24786D)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(0, size.height - 12),
      Offset(size.width, size.height - 12),
      axisPaint,
    );

    if (viewport.stages.isEmpty) {
      return;
    }

    final path = Path();
    for (var index = 0; index < viewport.stages.length; index++) {
      final stage = viewport.stages[index];
      final x = size.width * (index + 0.5) / viewport.stages.length;
      final y = 12 + stage.code.clamp(0, 4) * ((size.height - 24) / 4);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant HypnogramPainter oldDelegate) {
    return oldDelegate.viewport != viewport;
  }
}
