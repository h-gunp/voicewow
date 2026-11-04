import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Pretendard 1.3.9',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
    yield LicenseEntryWithLineBreaks(
      ['Supertonic 3 model'],
      'Supertonic 3 · Supertone\nhttps://huggingface.co/supertone-oss-archive/supertonic-3\n'
      '이 모델은 BigScience Open RAIL-M 5항과 첨부 A의 이용 제한을 따릅니다.\n\n'
      '${await rootBundle.loadString('web/prosody/vendor/supertonic/LICENSE-model.txt')}',
    );
  });
  runApp(
    VoiceMateApp(
      startWithPronunciation:
          !kIsWeb || Uri.base.queryParameters['feature'] == 'pronunciation',
    ),
  );
}
