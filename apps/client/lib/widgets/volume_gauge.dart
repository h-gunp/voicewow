import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../scenario.dart';

class VolumeGauge extends StatelessWidget {
  final Scenario scenario;
  final double? displayLevel;
  final double? lower, upper;
  const VolumeGauge({
    super.key,
    required this.scenario,
    this.displayLevel,
    this.lower,
    this.upper,
  });
  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final large = MediaQuery.textScalerOf(context).scale(14) > 20;
    final railHeight = (large ? 310.0 : 260.0) * scale;
    final low = lower ?? scenario.referenceLower.toDouble();
    final high = upper ?? scenario.referenceUpper.toDouble();
    return SizedBox(
      height: railHeight + 40,
      child: LayoutBuilder(
        builder: (context, box) {
          const top = 20.0;
          final railWidth = large ? 52.0 : 72.0;
          final left = large ? 10.0 : (box.maxWidth - railWidth) / 2;
          Widget marker(double value, String name, Key key) {
            final label = value == value.roundToDouble()
                ? value.toInt().toString()
                : value.toStringAsFixed(1);
            final y = top + (1 - value / 120) * railHeight;
            return Positioned(
              top: y,
              left: left - 10,
              right: 0,
              child: FractionalTranslation(
                translation: const Offset(0, -.5),
                child: Row(
                  children: [
                    Container(
                      key: Key('reference-line-$label'),
                      width: railWidth + 20,
                      height: 2,
                      color: red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$name $label',
                        key: key,
                        style: const TextStyle(
                          color: red,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return Semantics(
            label: '발화로 판정된 입력 수준과 상황별 참고 범위, 하한 $low, 상한 $high',
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (!large)
                  for (final value in [0, 20, 40, 60, 80, 100, 120])
                    Positioned(
                      left: left - 44,
                      top: top + (1 - value / 120) * railHeight,
                      width: 32,
                      child: FractionalTranslation(
                        translation: const Offset(0, -.5),
                        child: ExcludeSemantics(
                          child: Text(
                            '$value',
                            textAlign: TextAlign.right,
                            style: const TextStyle(color: muted, fontSize: 11),
                          ),
                        ),
                      ),
                    ),
                Positioned(
                  left: left,
                  top: top,
                  width: railWidth,
                  height: railHeight,
                  child: DecoratedBox(
                    key: const Key('gauge-rail'),
                    decoration: BoxDecoration(
                      color: const Color(0xffe8ece5),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: line),
                    ),
                  ),
                ),
                if (displayLevel != null)
                  Positioned(
                    left: left,
                    top: top,
                    width: railWidth,
                    height: railHeight,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(
                          // A newly detected syllable must start at its measured level.
                          begin: (displayLevel! / 120).clamp(0.0, 1.0),
                          end: (displayLevel! / 120).clamp(0.0, 1.0),
                        ),
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 150),
                        curve: Curves.easeOut,
                        builder: (context, fraction, child) => Align(
                          alignment: Alignment.bottomCenter,
                          child: SizedBox(
                            key: const Key('input-fill'),
                            width: railWidth,
                            height: railHeight * fraction,
                            child: child,
                          ),
                        ),
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: ink, width: 3),
                            ),
                            color: blue,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: left + 1,
                  top: top + (1 - high / 120) * railHeight,
                  width: railWidth - 2,
                  height: (high - low) / 120 * railHeight,
                  child: ColoredBox(color: red.withValues(alpha: .07)),
                ),
                marker(high, '상한', const Key('reference-upper')),
                marker(low, '하한', const Key('reference-lower')),
              ],
            ),
          );
        },
      ),
    );
  }
}
