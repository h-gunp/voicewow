import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../audio/audio_analysis.dart';

const _guide = Color(0xff2f62d6);
const _voice = Color(0xff34455e);

/// Feature contours, not raw waveform or a normative score. During recording
/// the horizontal axis is elapsed time; final traces may be DTW-aligned.
class ProsodyChart extends StatelessWidget {
  const ProsodyChart({
    super.key,
    this.reference,
    this.trace = const [],
    this.volume = false,
    this.live = false,
    this.progress,
    this.selected,
    this.regions = const [],
    this.domainSeconds,
    this.scaleBound,
    this.height = 270,
  });
  final AudioAnalysis? reference;
  final List<AudioFrame> trace;
  final bool volume, live;
  final double? progress, domainSeconds, scaleBound;
  final Segment? selected;
  final List<Segment> regions;
  final double height;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label:
        '${volume ? '상대적인 소리 크기' : '상대적인 음높이'} 그래프. 파란 점선은 가이드, 짙은 회색 선과 점은 내 목소리. '
        '${live ? '가로축은 녹음 경과 시간입니다.' : '가로축은 시간이며, 표시한 구간은 단어나 음절 경계가 아닙니다.'}'
        '${!live && regions.isNotEmpty ? ' 비교 구간: ${regions.map((region) => region.label).join(', ')}.' : ''}'
        '${selected == null ? '' : ' 선택한 구간: ${selected!.label}.'} 확인할 수 없는 소리는 선을 비워 둡니다.',
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Wrap(
            spacing: 18,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            children: [
              _Legend('가이드', _guide, dashed: true),
              _Legend('내 목소리', _voice),
            ],
          ),
        ),
        SizedBox(
          height: height * (MediaQuery.textScalerOf(context).scale(12) / 12),
          width: double.infinity,
          child: CustomPaint(
            painter: _ProsodyPainter(
              reference: reference,
              trace: trace,
              volume: volume,
              live: live,
              progress: progress,
              selected: selected,
              regions: regions,
              domainSeconds: domainSeconds,
              scaleBound: scaleBound,
              textScale: MediaQuery.textScalerOf(context).scale(12) / 12,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend(this.label, this.color, {this.dashed = false});
  final String label;
  final Color color;
  final bool dashed;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ...List.generate(
        dashed ? 3 : 1,
        (_) => Container(
          width: dashed ? 7 : 25,
          height: dashed ? 3 : 4,
          margin: const EdgeInsets.only(right: 3),
          color: color,
        ),
      ),
      const SizedBox(width: 4),
      Text(
        label,
        style: const TextStyle(fontSize: 14, color: Color(0xff465a74)),
      ),
    ],
  );
}

class _ProsodyPainter extends CustomPainter {
  _ProsodyPainter({
    required this.reference,
    required this.trace,
    required this.volume,
    required this.live,
    required this.progress,
    required this.selected,
    required this.regions,
    required this.domainSeconds,
    required this.scaleBound,
    required this.textScale,
  });
  final AudioAnalysis? reference;
  final List<AudioFrame> trace;
  final bool volume, live;
  final double? progress, domainSeconds, scaleBound;
  final double textScale;
  final Segment? selected;
  final List<Segment> regions;
  double? value(AudioFrame f) => volume ? f.relativeDb : f.relativePitch;
  bool measured(AudioFrame f) =>
      f.time.isFinite && value(f) != null && value(f)!.isFinite;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 80 || size.height < 100) return;
    final plot = Rect.fromLTRB(
      43 * textScale,
      35 * textScale,
      size.width - 12,
      size.height - 43 * textScale,
    );
    final ref = reference?.frames ?? const <AudioFrame>[];
    final all = [...ref, ...trace];
    var bound = volume ? 10.0 : 5.0;
    if (scaleBound != null && scaleBound!.isFinite && scaleBound! > 0) {
      bound = math.max(bound, scaleBound!);
    }
    var domain = math.max(.1, reference?.duration ?? 0.0);
    if (domainSeconds != null &&
        domainSeconds!.isFinite &&
        domainSeconds! > 0) {
      domain = math.max(domain, domainSeconds!);
    }
    for (final frame in all) {
      if (measured(frame)) bound = math.max(bound, value(frame)!.abs() * 1.12);
    }
    for (final frame in trace) {
      if (frame.time.isFinite) domain = math.max(domain, frame.time);
    }
    double x(double time) =>
        plot.left + (time / domain).clamp(0.0, 1.0) * plot.width;
    double y(double v) => plot.center.dy - v / bound * plot.height / 2;
    final regionDuration = live ? domain : reference?.duration ?? domain;
    final displayRegions = live ? const <Segment>[] : regions;
    final showTime = displayRegions.length <= 1;
    final bands = displayRegions.isEmpty
        ? [
            (0.0, regionDuration / 3),
            (regionDuration / 3, regionDuration * 2 / 3),
            (regionDuration * 2 / 3, regionDuration),
          ]
        : displayRegions.map((region) => (region.start, region.end)).toList();
    for (var i = 0; i < bands.length; i++) {
      canvas.drawRect(
        Rect.fromLTRB(x(bands[i].$1), plot.top, x(bands[i].$2), plot.bottom),
        Paint()
          ..color = i.isOdd ? const Color(0xfff8fafc) : const Color(0xfff0f5fc),
      );
    }
    if (selected != null) {
      final area = Rect.fromLTRB(
        x(selected!.start),
        plot.top,
        x(selected!.end),
        plot.bottom,
      );
      canvas.drawRect(area, Paint()..color = const Color(0xffeaf1fe));
      canvas.drawRect(
        area.deflate(1),
        Paint()
          ..color = const Color(0xff7c9fe0)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    final grid = Paint()
      ..color = const Color(0xffdce5f2)
      ..strokeWidth = 1;
    canvas.drawLine(plot.topLeft, plot.topRight, grid);
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, grid);
    for (final time in {
      0.0,
      ...bands.expand((band) => [band.$1, band.$2]),
    }) {
      canvas.drawLine(
        Offset(x(time), plot.top),
        Offset(x(time), plot.bottom),
        grid,
      );
    }
    _dash(
      canvas,
      Path()
        ..moveTo(plot.left, y(0))
        ..lineTo(plot.right, y(0)),
      Paint()
        ..color = const Color(0xffa8b8cf)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
      dash: 4,
      gap: 5,
    );
    _text(canvas, volume ? '소리 크기' : '음 높이', Offset(plot.left, 5), bold: true);
    _text(
      canvas,
      live ? '녹음 중 기준 갱신' : '각 목소리의 중간값 기준',
      Offset(plot.right, 6),
      align: TextAlign.right,
      font: 12,
      maxWidth: plot.width * .65,
    );
    _text(
      canvas,
      volume ? '큼' : '높음',
      Offset(plot.left - 8, plot.top),
      align: TextAlign.right,
      bold: true,
    );
    _text(
      canvas,
      '기준',
      Offset(plot.left - 8, y(0) - 7 * textScale),
      align: TextAlign.right,
      font: 12,
    );
    _text(
      canvas,
      volume ? '작음' : '낮음',
      Offset(plot.left - 8, plot.bottom - 15),
      align: TextAlign.right,
      bold: true,
    );
    Path path(List<AudioFrame> frames) {
      final result = Path();
      var drawing = false;
      for (final frame in frames) {
        if (!measured(frame)) {
          drawing = false;
          continue;
        }
        if (drawing) {
          result.lineTo(x(frame.time), y(value(frame)!));
        } else {
          result.moveTo(x(frame.time), y(value(frame)!));
          drawing = true;
        }
      }
      return result;
    }

    final refPath = path(ref), userPath = path(trace);
    Paint stroke(Color color, double width) => Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    _dash(canvas, refPath, stroke(Colors.white, 8));
    canvas.drawPath(userPath, stroke(Colors.white, live ? 8 : 6.5));
    _dash(canvas, refPath, stroke(_guide, live ? 3.5 : 4.5));
    canvas.drawPath(userPath, stroke(_voice, live ? 5 : 3.3));
    for (var i = 0; i < trace.length; i++) {
      final frame = trace[i];
      if (!measured(frame)) continue;
      final current = live && i == trace.length - 1;
      final isolated =
          (i == 0 || !measured(trace[i - 1])) &&
          (i + 1 == trace.length || !measured(trace[i + 1]));
      if (!current && !isolated) continue;
      final center = Offset(x(frame.time), y(value(frame)!)),
          radius = current ? 6.0 : 3.5;
      canvas.drawCircle(center, radius + 2, Paint()..color = Colors.white);
      canvas.drawCircle(center, radius, Paint()..color = _voice);
    }
    if (live && reference != null && reference!.duration > 0) {
      final endX = x(reference!.duration);
      _dash(
        canvas,
        Path()
          ..moveTo(endX, plot.top)
          ..lineTo(endX, plot.bottom),
        stroke(const Color(0xff94b6ec), 1),
        dash: 3,
        gap: 5,
      );
      if (plot.right - endX > 57) {
        _text(canvas, '가이드 끝', Offset(endX + 4, plot.top + 24), font: 12);
      }
    }
    for (var i = 0; i < (showTime ? 3 : displayRegions.length); i++) {
      final time = showTime
          ? regionDuration * i / 2
          : (displayRegions[i].start + displayRegions[i].end) / 2;
      _text(
        canvas,
        showTime ? '${time.toStringAsFixed(1)}초' : displayRegions[i].label,
        Offset(x(time), plot.bottom + 14),
        align: showTime && i == 0
            ? TextAlign.left
            : showTime && i == 2
            ? TextAlign.right
            : TextAlign.center,
        font: 12,
        bold: true,
      );
    }
    if (progress != null && progress!.isFinite) {
      final current = trace.isNotEmpty && measured(trace.last);
      final color = live
          ? (current ? _voice : const Color(0xff7d8da5))
          : _guide;
      final xx = x(progress!),
          label = live ? (current ? '내 목소리' : '소리 확인 중') : '지금';
      canvas.drawLine(
        Offset(xx, plot.top),
        Offset(xx, plot.bottom),
        stroke(color, 1.7),
      );
      final tagWidth = math.min(
        (label.length > 5 ? 80.0 : 64.0) * textScale,
        plot.width,
      );
      final halfTag = math.min(tagWidth / 2, plot.width / 2);
      final tagX = xx
          .clamp(plot.left + halfTag, plot.right - halfTag)
          .toDouble();
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(tagX, plot.top + 5),
            width: tagWidth,
            height: 22 * textScale,
          ),
          const Radius.circular(5),
        ),
        Paint()..color = color,
      );
      _text(
        canvas,
        label,
        Offset(tagX, plot.top - 3),
        align: TextAlign.center,
        color: Colors.white,
        font: 12,
        bold: true,
      );
    }
    if (!all.any(measured)) {
      _text(
        canvas,
        '녹음하면 내 목소리가 나타나요',
        Offset(plot.center.dx, plot.center.dy - 8),
        align: TextAlign.center,
        font: 12,
      );
    }
  }

  void _dash(
    Canvas canvas,
    Path path,
    Paint paint, {
    double dash = 9,
    double gap = 6,
  }) {
    for (final metric in path.computeMetrics()) {
      for (var offset = 0.0; offset < metric.length; offset += dash + gap) {
        canvas.drawPath(
          metric.extractPath(offset, math.min(metric.length, offset + dash)),
          paint,
        );
      }
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset offset, {
    TextAlign align = TextAlign.left,
    Color color = const Color(0xff465a74),
    double font = 12,
    double maxWidth = double.infinity,
    bool bold = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: font * textScale,
          color: color,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: maxWidth);
    final dx = align == TextAlign.center
        ? painter.width / 2
        : align == TextAlign.right
        ? painter.width
        : 0;
    painter.paint(canvas, Offset(offset.dx - dx, offset.dy));
  }

  @override
  bool shouldRepaint(covariant _ProsodyPainter oldDelegate) => true;
}
