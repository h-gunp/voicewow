package com.voicewow.voicemate

import android.os.Handler
import android.os.Looper
import ai.onnxruntime.OnnxJavaType
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import ai.onnxruntime.TensorInfo
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URI
import java.nio.FloatBuffer
import java.security.MessageDigest
import java.util.concurrent.Executors

internal object PronunciationPcm {
    fun prepareSamples(samples: FloatArray, sampleRate: Int): FloatArray {
        require(sampleRate == 16000 && samples.size in 3200..320000) {
            "16kHz 모노 음성을 0.2초 이상 20초 이하로 녹음해야 한다."
        }
        require(samples.all { it.isFinite() && it in -1.001f..1.001f }) { "오디오 값이 올바르지 않다." }
        val rawMean = samples.sumOf { it.toDouble() } / samples.size
        val variance = samples.sumOf { (it - rawMean) * (it - rawMean) } / samples.size
        require(variance >= 1e-10) { "분석할 소리가 없거나 너무 작다. 다시 녹음해야 한다." }
        // The pinned model's feature extractor uses raw PCM with do_normalize=false.
        return samples
    }

    fun decode(logits: FloatArray, shape: LongArray, vocab: Array<String>): List<String> {
        require(shape.size == 3 && shape[0] == 1L && shape[1] in 1L..1000L &&
            shape[2] == 55L && logits.size.toLong() == shape[1] * 55 &&
            vocab.size == 55 && vocab[0] == "[PAD]" && vocab[51] == " ") { "음소 모델 출력 형식이 올바르지 않다." }
        val phones = mutableListOf<String>()
        val vowels = setOf("a", "ɑ", "i", "u", "o", "ɛ", "ɯ", "ʌ", "ja", "jʌ",
            "jo", "ju", "jɛ", "wa", "wi", "wɛ", "wʌ", "ɰi")
        var previous = -1
        var lastId = -1
        var lastEnd = -1
        repeat(shape[1].toInt()) { frame ->
            val offset = frame * 55
            var id = 0
            var bestScore = logits[offset] + 0.5f
            repeat(55) { column ->
                val score = logits[offset + column]
                require(score.isFinite()) { "분석 결과에 유효하지 않은 수치가 있다." }
                if (score > bestScore) {
                    bestScore = score
                    id = column
                }
            }
            if (id != 0) {
                if (id != 51 && id != previous) {
                    // shortcut: one-frame vowel gaps count as continuation; rapid hiatus needs acoustic boundary detection.
                    val mergeVowel = previous == 0 && frame - lastEnd == 1 &&
                        lastId == id && vocab[id] in vowels
                    if (!mergeVowel) phones.add(vocab[id])
                }
                lastId = id
                lastEnd = frame + 1
            }
            previous = id
        }
        return phones
    }
}

// Main-thread mutations and worker reads share one generation; an old screen cannot retire a new owner.
internal class PronunciationLease {
    @Volatile private var owner = -1L
    @Volatile private var generation = 0L
    @Synchronized fun claim(session: Long): Long { owner = session; return ++generation }
    fun current(session: Long, ticket: Long) = owner == session && generation == ticket
    fun ownedBy(session: Long) = owner == session
    @Synchronized fun cancel(session: Long): Boolean {
        if (owner != session) return false
        generation++
        return true
    }
    @Synchronized fun withCurrent(session: Long, ticket: Long, action: () -> Unit): Boolean {
        if (!current(session, ticket)) return false
        action()
        return true
    }
    @Synchronized fun retire() { owner = -1; generation++ }
}

internal fun removeInterruptedModelParts(directory: File) {
    if (!directory.exists()) return
    check(directory.isDirectory) { "모델 저장 경로를 사용할 수 없다." }
    val files = checkNotNull(directory.listFiles()) { "모델 저장 공간을 확인하지 못했다." }
    for (file in files) {
        if (file.isFile && file.name.startsWith("model-") && file.name.endsWith(".part")) {
            check(file.delete() || !file.exists()) { "중단된 모델 다운로드 파일을 정리하지 못했다." }
        }
    }
}

class PronunciationEngine(private val cacheRoot: File, private val channel: MethodChannel,
    private val diagnosticsRoot: File? = null) :
    MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val lease = PronunciationLease()
    @Volatile private var closed = false
    @Volatile private var connection: HttpURLConnection? = null
    private var pending: Pending? = null
    // Only the worker touches these native resources, including their release after an active run.
    private var model: OrtSession? = null
    private var vocab: Array<String>? = null

    init { channel.setMethodCallHandler(this) }

    private class Pending(val session: Long, val request: Long, val ticket: Long,
        val result: MethodChannel.Result) {
        var completed = false
        fun cancelled() {
            if (!completed) { completed = true; result.error("cancelled", "음성 분석을 취소했다.", null) }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        val session = (arguments?.get("session") as? Number)?.toLong()
        if (closed || session == null || session < 1) {
            result.error("unavailable", "음성 분석 연결을 사용할 수 없다.", null)
            return
        }
        when (call.method) {
            "cancel", "dispose" -> {
                if (lease.cancel(session)) {
                    pending?.cancelled()
                    pending = null
                    connection?.disconnect()
                    if (call.method == "dispose") worker.execute { releaseModel() }
                }
                result.success(null)
            }
            "prepare", "recognize" -> {
                val request = (arguments["request"] as? Number)?.toLong()
                if (request == null || (call.method == "recognize" && !lease.ownedBy(session))) {
                    result.error("unavailable", "분석 준비를 다시 시작해야 한다.", null)
                    return
                }
                if (call.method == "recognize" && pending != null) {
                    result.error("busy", "진행 중인 음성 분석을 먼저 마쳐야 한다.", null)
                    return
                }
                pending?.cancelled()
                connection?.disconnect()
                val operation = Pending(session, request, lease.claim(session), result)
                pending = operation
                val samples = arguments["samples"] as? FloatArray
                val sampleRate = (arguments["sampleRate"] as? Number)?.toInt()
                val diagnosticRaw = arguments["diagnosticRawPcm48"] as? ByteArray
                val diagnosticSpeech = arguments["diagnosticSpeech"] as? IntArray
                worker.execute {
                    try {
                        checkCurrent(operation)
                        val value = if (call.method == "prepare") {
                            prepare(operation)
                            null
                        } else {
                            require(samples != null && sampleRate != null) { "녹음된 소리를 읽지 못했다." }
                            recognize(samples, sampleRate, operation, diagnosticRaw, diagnosticSpeech)
                        }
                        complete(operation, value, null)
                    } catch (error: Exception) {
                        complete(operation, null, error)
                    } catch (error: OutOfMemoryError) {
                        releaseModel()
                        complete(operation, null, IllegalStateException("기기의 메모리가 부족하다. 다른 앱을 닫고 다시 시도해야 한다."))
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun complete(operation: Pending, value: Any?, error: Exception?) {
        main.post {
            if (!operation.completed) {
                operation.completed = true
                if (!lease.current(operation.session, operation.ticket) || closed) {
                    operation.result.error("cancelled", "음성 분석을 취소했다.", null)
                } else if (error != null) {
                    operation.result.error("analysis_failed", error.message ?: "음성 분석에 실패했다.", null)
                } else operation.result.success(value)
            }
            if (pending === operation) pending = null
        }
    }

    private fun checkCurrent(operation: Pending) {
        check(!closed && lease.current(operation.session, operation.ticket)) { "음성 분석을 취소했다." }
    }

    private fun progress(operation: Pending, message: String) {
        main.post {
            if (!closed && lease.current(operation.session, operation.ticket)) {
                channel.invokeMethod("progress", mapOf("session" to operation.session,
                    "request" to operation.request, "message" to message))
            }
        }
    }

    private fun prepare(operation: Pending) {
        if (model != null) return
        val files = synchronized(downloadLock) {
            checkCurrent(operation)
            // A replaced Flutter engine may still be closing its old download.
            removeInterruptedModelParts(File(cacheRoot, "pronunciation/$REVISION"))
            ASSETS.map { asset -> loadAsset(asset, operation) }
        }
        val config = JSONObject(files[0].readText())
        val vocabulary = JSONObject(files[1].readText())
        val added = JSONObject(files[2].readText())
        added.keys().forEach { vocabulary.put(it, added.getInt(it)) }
        val processor = JSONObject(files[3].readText())
        require(config.getInt("vocab_size") == 55 && config.getInt("pad_token_id") == 0 &&
            vocabulary.length() == 55 && processor.getInt("sampling_rate") == 16000 &&
            !processor.getBoolean("do_normalize")) { "지원하지 않는 음소 모델 설정이다." }
        val labels = Array(55) { "" }
        vocabulary.keys().forEach {
            val id = vocabulary.getInt(it)
            require(id in labels.indices && labels[id].isEmpty()) { "음소 사전이 올바르지 않다." }
            labels[id] = it
        }
        require(labels[0] == "[PAD]" && labels[51] == " " && labels.all { it.isNotEmpty() })
        checkCurrent(operation)
        progress(operation, "기기에서 음소 모델을 여는 중이다.")
        val loaded = OrtSession.SessionOptions().use { options ->
            options.setIntraOpNumThreads(1)
            options.setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
            OrtEnvironment.getEnvironment().createSession(files[4].absolutePath, options)
        }
        var retained = false
        try {
            require(loaded.inputNames == setOf("input_values") && loaded.outputNames == setOf("logits")) {
                "지원하지 않는 음소 모델 입출력이다."
            }
            val input = loaded.inputInfo["input_values"]?.info as? TensorInfo
            val output = loaded.outputInfo["logits"]?.info as? TensorInfo
            require(input?.type == OnnxJavaType.FLOAT && input.shape.size == 2 &&
                output?.type == OnnxJavaType.FLOAT && output.shape.size == 3 && output.shape[2] == 55L) {
                "지원하지 않는 음소 모델 입출력 형식이다."
            }
            checkCurrent(operation)
            model = loaded
            vocab = labels
            retained = true
        } finally {
            if (!retained) loaded.close()
        }
    }

    private fun recognize(samples: FloatArray, sampleRate: Int, operation: Pending,
        diagnosticRaw: ByteArray?, diagnosticSpeech: IntArray?): List<String> {
        val prepared = PronunciationPcm.prepareSamples(samples, sampleRate)
        val session = checkNotNull(model) { "분석 모델을 먼저 준비해야 한다." }
        val labels = checkNotNull(vocab)
        checkCurrent(operation)
        OnnxTensor.createTensor(OrtEnvironment.getEnvironment(), FloatBuffer.wrap(prepared),
            longArrayOf(1, prepared.size.toLong())).use { input ->
            session.run(mapOf("input_values" to input)).use { output ->
                checkCurrent(operation)
                val tensor = output.get("logits").orElse(null) as? OnnxTensor
                require(tensor != null && tensor.info.type == OnnxJavaType.FLOAT) { "음소 결과를 읽지 못했다." }
                val buffer = tensor.floatBuffer
                val logits = FloatArray(buffer.remaining())
                buffer.get(logits)
                val phones = PronunciationPcm.decode(logits, tensor.info.shape, labels)
                val directory = diagnosticsRoot
                if (diagnosticRaw != null && directory != null) {
                    // Optional local storage must never change a completed recognition result.
                    runCatching {
                        lease.withCurrent(operation.session, operation.ticket) {
                            if (!closed) LocalAudioDiagnostics(directory).save(diagnosticRaw, prepared, logits,
                                tensor.info.shape, diagnosticSpeech, labels, phones, REVISION)
                        }
                    }
                }
                return phones
            }
        }
    }

    private data class Asset(val path: String, val bytes: Long, val sha256: String,
        val sourceUrl: String = "$MODEL_SOURCE/$path")

    private fun loadAsset(asset: Asset, operation: Pending): File {
        val directory = File(cacheRoot, "pronunciation/$REVISION")
        check(directory.isDirectory || directory.mkdirs()) { "모델 저장 공간을 만들지 못했다." }
        val target = File(directory, asset.path.replace('/', '_'))
        progress(operation, "음소 모델 파일을 확인하는 중이다.")
        if (target.isFile && validAsset(target, asset, operation)) return target
        checkCurrent(operation)
        val temporary = File.createTempFile("model-", ".part", directory)
        try {
            val http = (URI(asset.sourceUrl).toURL()
                .openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 30000
                readTimeout = 30000
            }
            connection = http
            try {
                checkCurrent(operation)
                require(http.responseCode == 200) { "모델 다운로드에 실패했다. 연결을 확인해야 한다." }
                var received = 0L
                var percent = -1
                http.inputStream.use { input ->
                    temporary.outputStream().use { output ->
                        val buffer = ByteArray(65536)
                        while (true) {
                            checkCurrent(operation)
                            val count = input.read(buffer)
                            if (count < 0) break
                            received += count
                            require(received <= asset.bytes) { "모델 파일 크기가 올바르지 않다." }
                            output.write(buffer, 0, count)
                            val next = (received * 100 / asset.bytes).toInt()
                            if (asset.bytes > 1000000 && next != percent) {
                                percent = next
                                progress(operation, "음소 모델을 내려받는 중이다. $percent% (약 378MB)")
                            }
                        }
                    }
                }
            } finally {
                if (connection === http) connection = null
                http.disconnect()
            }
            require(validAsset(temporary, asset, operation)) { "모델 파일 검증에 실패했다. 다시 내려받아야 한다." }
            checkCurrent(operation)
            check((!target.exists() || target.delete()) && temporary.renameTo(target)) { "모델 파일을 저장하지 못했다." }
            return target
        } finally { temporary.delete() }
    }

    private fun validAsset(file: File, asset: Asset, operation: Pending): Boolean {
        if (file.length() != asset.bytes) return false
        val hash = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(65536)
            while (true) {
                checkCurrent(operation)
                val count = input.read(buffer)
                if (count < 0) break
                hash.update(buffer, 0, count)
            }
        }
        return hash.digest().joinToString("") { "%02x".format(it) } == asset.sha256
    }

    private fun releaseModel() {
        try { model?.close() } finally { model = null; vocab = null }
    }

    fun close() {
        synchronized(lease) {
            if (closed) return
            closed = true
            lease.retire()
        }
        pending?.cancelled()
        pending = null
        connection?.disconnect()
        channel.setMethodCallHandler(null)
        worker.execute { releaseModel() }
        worker.shutdown()
    }

    companion object {
        private val downloadLock = Any()
        private const val REVISION = "772950d64427910937e11c5b76c9e4594059ce8c"
        private const val MODEL_SOURCE = "https://huggingface.co/icig/normal-korean-ipa-translation/resolve/$REVISION"
        private val ASSETS = listOf(
            Asset("config.json", 2369, "fabc5f4a4238971ae1399ca5f3e591ae5beb142fdd2b3804a20e6700649ea83e"),
            Asset("vocab.json", 645, "7027b570bda6e7ea7a3b3b44f1e8198e2d521f9b57a7857579ac7001e0cb72f1"),
            Asset("added_tokens.json", 30, "843da62c8cdea9fb78b7303dc873d0988c7debf7e1c9903e8dfd22c1705f31a2"),
            Asset("preprocessor_config.json", 258, "3698647300e38b0a83ccf0ee9b24834e2d262157410305d54a3a1f655ead3002"),
            Asset("ko-ipa.onnx", 282052, "840b1a2f19d1b2c52ac5ef522764d5e5fb42ad79a0b839805904ed1b6b36f949",
                "https://raw.githubusercontent.com/h-gunp/voicewow/4972547545da42780de509218990714eb7a12f7a/apps/client/web/pronunciation/models/ko-ipa.onnx"),
            Asset("model.safetensors", 377681876, "dfe465932554b8d8d5ff818afb27995fc7ac20e6af7e3b77f26a8aa7e7dc0404"),
        )
    }
}
