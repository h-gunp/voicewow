import 'package:flutter/widgets.dart';

class ProsodyWebSurface extends StatelessWidget {
  const ProsodyWebSurface({super.key, this.onExit, this.suspended = false});
  final Future<void> Function()? onExit;
  final bool suspended;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
