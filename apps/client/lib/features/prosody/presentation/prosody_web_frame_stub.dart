import 'package:flutter/widgets.dart';

/// Kept out of the native practice flow by ProsodyScreen's web-only branch.
class ProsodyWebFrame extends StatelessWidget {
  const ProsodyWebFrame({super.key, this.onExit});
  final Future<void> Function()? onExit;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
