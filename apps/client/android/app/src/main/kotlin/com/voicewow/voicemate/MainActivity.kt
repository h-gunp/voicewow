package com.voicewow.voicemate

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pronunciation: PronunciationEngine? = null
    private var volume: VolumeEngine? = null
    private var practiceAudio: PracticeAudioEngine? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pronunciation?.close()
        pronunciation = PronunciationEngine(
            cacheDir,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "voicemate/pronunciation"),
        )
        volume?.close()
        volume = VolumeEngine(
            applicationContext,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "voicemate/volume"),
        )
        practiceAudio?.close()
        practiceAudio = PracticeAudioEngine(
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "voicemate/practice_audio"),
        )
    }

    override fun onStop() {
        volume?.suspendCapture()
        super.onStop()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        pronunciation?.close()
        pronunciation = null
        volume?.close()
        volume = null
        practiceAudio?.close()
        practiceAudio = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
