import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../scenario.dart';

class VolumeGauge extends StatelessWidget {
  final Scenario scenario;
  final double? displayLevel;
  const VolumeGauge({super.key, required this.scenario, this.displayLevel});
  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final railHeight = 310.0 * scale;
    return SizedBox(
      height: railHeight + 40,
      child: LayoutBuilder(
        builder: (context, box) {
          const railWidth = 72.0, top = 20.0;
          final large = MediaQuery.textScalerOf(context).scale(14) > 20;
          final left = large ? 18.0 : (box.maxWidth - railWidth) / 2;
          Widget marker(int value, String name, Key key) {
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
                      key: Key('reference-line-$value'),
                      width: railWidth + 20,
                      height: 2,
                      color: red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$name $value',
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
            label:
                '발화로 판정된 입력 수준과 상황별 참고 범위, 하한 ${scenario.referenceLower}, 상한 ${scenario.referenceUpper}',
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: left,
                  top: top,
                  width: railWidth,
                  height: railHeight,
                  child: DecoratedBox(
                    key: const Key('gauge-rail'),
                    decoration: BoxDecoration(
                      color: const Color(0xffeaf0f5),
                      borderRadius: BorderRadius.circular(40),
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
                      borderRadius: BorderRadius.circular(40),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(
                          begin: 0,
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
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [blue, Color(0xff8ab5ff)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: left + 1,
                  top: top + (1 - scenario.referenceUpper / 120) * railHeight,
                  width: railWidth - 2,
                  height:
                      (scenario.referenceUpper - scenario.referenceLower) /
                      120 *
                      railHeight,
                  child: ColoredBox(color: red.withValues(alpha: .07)),
                ),
                marker(
                  scenario.referenceUpper,
                  '상한',
                  const Key('reference-upper'),
                ),
                marker(
                  scenario.referenceLower,
                  '하한',
                  const Key('reference-lower'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
