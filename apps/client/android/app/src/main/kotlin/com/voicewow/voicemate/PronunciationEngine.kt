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
import kotlin.math.abs
import kotlin.math.sqrt

internal object PronunciationPcm {
    fun normalize(samples: FloatArray, sampleRate: Int): FloatArray {
        require(sampleRate == 16000 && samples.size in 3200..320000) {
            "16kHz 모노 음성을 0.2초 이상 20초 이하로 녹음해야 한다."
        }
        require(samples.all { it.isFinite() && it in -1.001f..1.001f }) { "오디오 값이 올바르지 않다." }
        val rawMean = samples.sumOf { it.toDouble() } / samples.size
        val variance = samples.sumOf { (it - rawMean) * (it - rawMean) } / samples.size
        require(variance >= 1e-10) { "분석할 소리가 없거나 너무 작다. 다시 녹음해야 한다." }
        val threshold = maxOf(samples.maxOf { abs(it.toDouble()) } * 0.01, 1e-4)
        val first = samples.indexOfFirst { abs(it.toDouble()) >= threshold }
        var input = samples
        if (first >= 0) {
            val last = samples.indexOfLast { abs(it.toDouble()) >= threshold }
            val length = last - first + 1 + 12800
            // Match the web path's sample-level 400 ms context without cutting speech.
            if (length <= 320000) {
                val start = first - 6400
                input = FloatArray(length) { samples.getOrElse(start + it) { 0f } }
            }
        }
        val mean = input.sumOf { it.toDouble() } / input.size
        val inputVariance = input.sumOf { (it - mean) * (it - mean) } / input.size
        require(inputVariance.isFinite() && inputVariance > 0) { "분석할 소리가 없거나 너무 작다. 다시 녹음해야 한다." }
        val scale = sqrt(inputVariance)
        return FloatArray(input.size) { ((input[it] - mean) / scale).toFloat() }
    }

    fun decode(logits: FloatArray, shape: LongArray, vocab: Array<String>): List<String> {
        require(shape.size == 3 && shape[0] == 1L && shape[1] in 1L..1000L &&
            shape[2] == 45L && logits.size.toLong() == shape[1] * 45 &&
            vocab.size == 45 && vocab[42] == "[PAD]") { "음소 모델 출력 형식이 올바르지 않다." }
        val phones = mutableListOf<String>()
        var previous = -1
        repeat(shape[1].toInt()) { frame ->
            val offset = frame * 45
            var id = 0
            repeat(45) { column ->
                require(logits[offset + column].isFinite()) { "분석 결과에 유효하지 않은 수치가 있다." }
                if (logits[offset + column] > logits[offset + id]) id = column
            }
            if (id != 42 && id != 40 && id != previous) phones.add(vocab[id])
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

class PronunciationEngine(private val cacheRoot: File, private val channel: MethodChannel) :
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
                worker.execute {
                    try {
                        checkCurrent(operation)
                        val value = if (call.method == "prepare") {
                            prepare(operation)
                            null
                        } else {
                            require(samples != null && sampleRate != null) { "녹음된 소리를 읽지 못했다." }
                            recognize(samples, sampleRate, operation)
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
        require(config.getInt("vocab_size") == 45 && config.getInt("pad_token_id") == 42 &&
            vocabulary.length() == 45 && processor.getInt("sampling_rate") == 16000 &&
            processor.getBoolean("do_normalize")) { "지원하지 않는 음소 모델 설정이다." }
        val labels = Array(45) { "" }
        vocabulary.keys().forEach {
            val id = vocabulary.getInt(it)
            require(id in labels.indices && labels[id].isEmpty()) { "음소 사전이 올바르지 않다." }
            labels[id] = it
        }
        require(labels[42] == "[PAD]" && labels[40] == "|" && labels.all { it.isNotEmpty() })
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
                output?.type == OnnxJavaType.FLOAT && output.shape.size == 3 && output.shape[2] == 45L) {
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

    private fun recognize(samples: FloatArray, sampleRate: Int, operation: Pending): List<String> {
        val normalized = PronunciationPcm.normalize(samples, sampleRate)
        val session = checkNotNull(model) { "분석 모델을 먼저 준비해야 한다." }
        val labels = checkNotNull(vocab)
        checkCurrent(operation)
        OnnxTensor.createTensor(OrtEnvironment.getEnvironment(), FloatBuffer.wrap(normalized),
            longArrayOf(1, normalized.size.toLong())).use { input ->
            session.run(mapOf("input_values" to input)).use { output ->
                checkCurrent(operation)
                val tensor = output.get("logits").orElse(null) as? OnnxTensor
                require(tensor != null && tensor.info.type == OnnxJavaType.FLOAT) { "음소 결과를 읽지 못했다." }
                val buffer = tensor.floatBuffer
                val logits = FloatArray(buffer.remaining())
                buffer.get(logits)
                return PronunciationPcm.decode(logits, tensor.info.shape, labels)
            }
        }
    }

    private data class Asset(val path: String, val bytes: Long, val sha256: String)

    private fun loadAsset(asset: Asset, operation: Pending): File {
        val directory = File(cacheRoot, "pronunciation/$REVISION")
        check(directory.isDirectory || directory.mkdirs()) { "모델 저장 공간을 만들지 못했다." }
        val target = File(directory, asset.path.replace('/', '_'))
        progress(operation, "음소 모델 파일을 확인하는 중이다.")
        if (target.isFile && validAsset(target, asset, operation)) return target
        checkCurrent(operation)
        val temporary = File.createTempFile("model-", ".part", directory)
        try {
            val http = (URI("https://huggingface.co/chegrowk/ko-phone-int8/resolve/$REVISION/${asset.path}").toURL()
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
                                progress(operation, "음소 모델을 내려받는 중이다. $percent% (약 356MB)")
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
        if (closed) return
        closed = true
        pending?.cancelled()
        pending = null
        connection?.disconnect()
        channel.setMethodCallHandler(null)
        worker.execute { releaseModel() }
        worker.shutdown()
    }

    companion object {
        private val downloadLock = Any()
        private const val REVISION = "dbb9c196f3e5e72d41c8ce2b63e6d0c91a011b70"
        private val ASSETS = listOf(
            Asset("config.json", 2063, "bc3394c2db0f96a9ab5e68c3a389201266bd21a26fcde109ff9d07accda26bd2"),
            Asset("vocab.json", 500, "ca2a65143ce6acf25913f7e354ca7bae767ddb39b99218713057ae117dc87fc9"),
            Asset("added_tokens.json", 30, "e6fbfcadb18a959fef9b7736b9f23fa2f5761674824f0db1263aaaf2e15e0959"),
            Asset("preprocessor_config.json", 279, "f6a6867d632ee397cab2eb1c6a49dc64d857bb085e0f0463705b0217f4b96da4"),
            Asset("onnx/model_quantized.onnx", 356129122, "c1ef511e4bac127e884edb013b16fae9e0d3d54d792039417aa3cf4b48e8a134"),
        )
    }
}
