import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    VoiceMateApp(
      startWithPronunciation:
          !kIsWeb || Uri.base.queryParameters['feature'] == 'pronunciation',
    ),
  );
}
