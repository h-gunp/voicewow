package com.voicewow.voicemate

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pronunciation: PronunciationEngine? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pronunciation?.close()
        pronunciation = PronunciationEngine(
            cacheDir,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "voicemate/pronunciation"),
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        pronunciation?.close()
        pronunciation = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
