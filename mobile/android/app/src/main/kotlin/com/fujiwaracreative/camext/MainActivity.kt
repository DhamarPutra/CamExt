package com.fujiwaracreative.camext

import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import java.io.ByteArrayOutputStream
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    private val CONTROL_CHANNEL = "com.fujiwaracreative.camext/control"
    private val STREAM_CHANNEL = "com.fujiwaracreative.camext/stream"

    private var eventSink: EventChannel.EventSink? = null
    private var executorService: ScheduledExecutorService? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var isCapturing = false
    private var mockFrameCount = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Method Channel untuk mengontrol Start/Stop Capture Kamera & Encoder
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CONTROL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startCapture" -> {
                    val codec = call.argument<Int>("codec") ?: 2
                    val width = call.argument<Int>("width") ?: 1920
                    val height = call.argument<Int>("height") ?: 1080
                    val fps = call.argument<Int>("fps") ?: 60

                    startMockCapture(codec, width, height, fps)
                    result.success(null)
                }
                "stopCapture" -> {
                    stopMockCapture()
                    result.success(null)
                }
                "yuvToJpeg" -> {
                    val y = call.argument<ByteArray>("y")
                    val u = call.argument<ByteArray>("u")
                    val v = call.argument<ByteArray>("v")
                    val yRowStride = call.argument<Int>("yRowStride") ?: 0
                    val uRowStride = call.argument<Int>("uRowStride") ?: 0
                    val vRowStride = call.argument<Int>("vRowStride") ?: 0
                    val uPixelStride = call.argument<Int>("uPixelStride") ?: 0
                    val vPixelStride = call.argument<Int>("vPixelStride") ?: 0
                    val width = call.argument<Int>("width") ?: 0
                    val height = call.argument<Int>("height") ?: 0
                    val quality = call.argument<Int>("quality") ?: 70
                    val rotation = call.argument<Int>("rotation") ?: 0

                    if (y != null && u != null && v != null && width > 0 && height > 0) {
                        try {
                            val jpegBytes = convertYuvToJpeg(
                                y, u, v,
                                yRowStride, uRowStride, vRowStride,
                                uPixelStride, vPixelStride,
                                width, height, quality
                            )
                            
                            var finalJpeg = jpegBytes
                            if (rotation != 0) {
                                val bitmap = BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size)
                                if (bitmap != null) {
                                    val matrix = Matrix()
                                    matrix.postRotate(rotation.toFloat())
                                    val rotatedBitmap = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
                                    val outRotated = ByteArrayOutputStream()
                                    rotatedBitmap.compress(Bitmap.CompressFormat.JPEG, quality, outRotated)
                                    finalJpeg = outRotated.toByteArray()
                                    bitmap.recycle()
                                    rotatedBitmap.recycle()
                                }
                            }
                            result.success(finalJpeg)
                        } catch (e: Exception) {
                            result.error("CONVERSION_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENTS", "Missing arguments", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // 2. Event Channel untuk mengirimkan data terkompresi ke Dart (60 FPS)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, STREAM_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    stopMockCapture()
                }
            }
        )
    }

    private fun startMockCapture(codec: Int, width: Int, height: Int, fps: Int) {
        if (isCapturing) return
        isCapturing = true
        mockFrameCount = 0

        executorService = Executors.newSingleThreadScheduledExecutor()
        
        // Menentukan interval waktu berdasarkan FPS target
        val intervalMs = (1000 / fps).toLong()

        // Dummy payload untuk H.264 (NAL units tiruan) atau MJPEG
        // Kami membuat data terkompresi tiruan seolah-olah ditransmisikan oleh hardware encoder
        val dummyPayload = ByteArray(1024) { index -> (index % 256).toByte() }

        executorService?.scheduleAtFixedRate({
            if (!isCapturing) return@scheduleAtFixedRate

            mockFrameCount++
            
            // Kirim frame tiruan ke Dart thread utama
            mainHandler.post {
                eventSink?.success(dummyPayload)
            }
        }, 0, intervalMs, TimeUnit.MILLISECONDS)
    }

    private fun stopMockCapture() {
        if (!isCapturing) return
        isCapturing = false
        
        executorService?.shutdown()
        try {
            executorService?.awaitTermination(500, TimeUnit.MILLISECONDS)
        } catch (e: InterruptedException) {
            e.printStackTrace()
        }
        executorService = null
    }

    private fun convertYuvToJpeg(
        y: ByteArray,
        u: ByteArray,
        v: ByteArray,
        yRowStride: Int,
        uRowStride: Int,
        vRowStride: Int,
        uPixelStride: Int,
        vPixelStride: Int,
        width: Int,
        height: Int,
        quality: Int
    ): ByteArray {
        val nv21 = ByteArray(width * height * 3 / 2)
        
        // Copy Y channel
        if (yRowStride == width) {
            System.arraycopy(y, 0, nv21, 0, width * height)
        } else {
            for (row in 0 until height) {
                val srcPos = row * yRowStride
                val length = Math.min(width, y.size - srcPos)
                if (length > 0) {
                    System.arraycopy(y, srcPos, nv21, row * width, length)
                }
            }
        }
        
        // Copy VU channel (interleaved V, U)
        val nvSize = width * height
        var pos = nvSize
        
        val chromaHeight = height / 2
        val chromaWidth = width / 2
        
        for (row in 0 until chromaHeight) {
            val uRowOffset = row * uRowStride
            val vRowOffset = row * vRowStride
            
            for (col in 0 until chromaWidth) {
                val uIdx = uRowOffset + col * uPixelStride
                val vIdx = vRowOffset + col * vPixelStride
                
                if (pos < nv21.size - 1) {
                    if (vIdx >= 0 && vIdx < v.size) {
                        nv21[pos++] = v[vIdx]
                    } else {
                        nv21[pos++] = 0
                    }
                    
                    if (uIdx >= 0 && uIdx < u.size) {
                        nv21[pos++] = u[uIdx]
                    } else {
                        nv21[pos++] = 0
                    }
                }
            }
        }
        
        val yuvImage = YuvImage(nv21, ImageFormat.NV21, width, height, null)
        val out = ByteArrayOutputStream()
        yuvImage.compressToJpeg(Rect(0, 0, width, height), quality, out)
        return out.toByteArray()
    }

    override fun onDestroy() {
        stopMockCapture()
        super.onDestroy()
    }
}
