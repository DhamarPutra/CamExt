package com.fujiwaracreative.camext

import android.content.Context
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.hardware.camera2.*
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.view.Surface
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.OutputStream
import java.net.Socket
import java.util.concurrent.Executors
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val CONTROL_CHANNEL = "com.fujiwaracreative.camext/control"

    private val mainHandler = Handler(Looper.getMainLooper())
    private val socketExecutor = Executors.newSingleThreadExecutor()
    private val processExecutor = Executors.newFixedThreadPool(3)

    private var socket: Socket? = null
    private var outputStream: OutputStream? = null
    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var imageReader: ImageReader? = null
    private var sequenceNumber = 0
    private var isStreamingNative = false
    
    private var isStreamingAudio = false
    private var audioRecord: AudioRecord? = null
    private var audioThread: Thread? = null
    
    private var cameraHandlerThread: HandlerThread? = null
    private var cameraHandler: Handler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CONTROL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startCapture" -> {
                    val ip = call.argument<String>("ip") ?: "127.0.0.1"
                    val port = call.argument<Int>("port") ?: 4455
                    val width = call.argument<Int>("width") ?: 1280
                    val height = call.argument<Int>("height") ?: 720
                    val enableAudio = call.argument<Boolean>("enableAudio") ?: false

                    startNativeCameraStream(ip, port, width, height, enableAudio)
                    result.success(null)
                }
                "stopCapture" -> {
                    stopNativeCameraStream()
                    result.success(null)
                }
                "getSupportedResolutions" -> {
                    val resolutions = getSupportedResolutions()
                    result.success(resolutions)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun startNativeCameraStream(ip: String, port: Int, width: Int, height: Int, enableAudio: Boolean) {
        if (isStreamingNative) return
        isStreamingNative = true
        sequenceNumber = 0

        cameraHandlerThread = HandlerThread("CameraHandlerThread").apply { start() }
        cameraHandler = Handler(cameraHandlerThread!!.looper)

        socketExecutor.submit {
            try {
                System.out.println("[*] Connecting native socket to $ip:$port...")
                socket = Socket(ip, port)
                outputStream = socket!!.getOutputStream()
                System.out.println("[+] Socket connected! Initializing native camera...")
                
                mainHandler.post {
                    initNativeCamera(width, height)
                }

                if (enableAudio) {
                    startAudioCapture()
                }
            } catch (e: Exception) {
                e.printStackTrace()
                stopNativeCameraStream()
            }
        }
    }

    private fun initNativeCamera(width: Int, height: Int) {
        try {
            val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val cameraId = cameraManager.cameraIdList.firstOrNull { id ->
                val chars = cameraManager.getCameraCharacteristics(id)
                chars.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
            } ?: cameraManager.cameraIdList[0]

            imageReader = ImageReader.newInstance(width, height, ImageFormat.JPEG, 2)
            imageReader?.setOnImageAvailableListener({ reader ->
                val image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
                if (!isStreamingNative) {
                    image.close()
                    return@setOnImageAvailableListener
                }

                try {
                    val planes = image.planes
                    if (planes.isNotEmpty()) {
                        val buffer = planes[0].buffer
                        val size = buffer.remaining()
                        val jpegBytes = ByteArray(size)
                        buffer.get(jpegBytes)
                        image.close()

                        processExecutor.submit {
                            sendFrame(jpegBytes)
                        }
                    } else {
                        image.close()
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                    image.close()
                }
            }, cameraHandler)

            cameraManager.openCamera(cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    cameraDevice = camera
                    startNativeCaptureSession()
                }

                override fun onDisconnected(camera: CameraDevice) {
                    stopNativeCameraStream()
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    System.err.println("[!] Native Camera error: $error")
                    stopNativeCameraStream()
                }
            }, cameraHandler)
        } catch (e: SecurityException) {
            e.printStackTrace()
            stopNativeCameraStream()
        } catch (e: Exception) {
            e.printStackTrace()
            stopNativeCameraStream()
        }
    }

    private fun startNativeCaptureSession() {
        val readerSurface = imageReader?.surface ?: return
        val outputs = listOf(readerSurface)
        
        cameraDevice?.createCaptureSession(outputs, object : CameraCaptureSession.StateCallback() {
            override fun onConfigured(session: CameraCaptureSession) {
                captureSession = session
                try {
                    val builder = cameraDevice!!.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
                    builder.addTarget(readerSurface)

                    // Disable heavy image post-processing for minimum latency & maximum FPS
                    try { builder.set(CaptureRequest.NOISE_REDUCTION_MODE, CaptureRequest.NOISE_REDUCTION_MODE_OFF) } catch (e: Exception) {}
                    try { builder.set(CaptureRequest.EDGE_MODE, CaptureRequest.EDGE_MODE_OFF) } catch (e: Exception) {}
                    try { builder.set(CaptureRequest.COLOR_CORRECTION_ABERRATION_MODE, CaptureRequest.COLOR_CORRECTION_ABERRATION_MODE_OFF) } catch (e: Exception) {}
                    try { builder.set(CaptureRequest.HOT_PIXEL_MODE, CaptureRequest.HOT_PIXEL_MODE_OFF) } catch (e: Exception) {}

                    // Konfigurasi target FPS range untuk mengaktifkan 60 FPS jika didukung
                    val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
                    val cameraId = cameraDevice?.id ?: "0"
                    val chars = cameraManager.getCameraCharacteristics(cameraId)
                    val fpsRanges = chars.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
                    if (fpsRanges != null) {
                        var bestRange: android.util.Range<Int>? = null
                        for (range in fpsRanges) {
                            if (range.upper == 60) {
                                if (bestRange == null || range.lower > bestRange.lower) {
                                    bestRange = range
                                }
                            }
                        }
                        if (bestRange != null) {
                            builder.set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, bestRange)
                            System.out.println("[+] Native Camera: Target AE FPS Range disetel ke $bestRange")
                        } else {
                            var highestUpperRange: android.util.Range<Int>? = null
                            for (range in fpsRanges) {
                                if (highestUpperRange == null || range.upper > highestUpperRange.upper) {
                                    highestUpperRange = range
                                }
                            }
                            if (highestUpperRange != null) {
                                builder.set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, highestUpperRange)
                                System.out.println("[+] Native Camera: Target AE FPS Range fallback disetel ke $highestUpperRange")
                            }
                        }
                    }

                    captureSession?.setRepeatingRequest(builder.build(), null, cameraHandler)
                    System.out.println("[+] Native camera capture session active.")
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }

            override fun onConfigureFailed(session: CameraCaptureSession) {
                stopNativeCameraStream()
            }
        }, cameraHandler)
    }

    private fun sendFrame(jpegBytes: ByteArray) {
        try {
            socketExecutor.submit {
                try {
                    val outStream = outputStream ?: return@submit
                    val header = ByteArray(20)
                    
                    header[0] = 0xCA.toByte()
                    header[1] = 0x5E.toByte()
                    header[2] = 0xCA.toByte()
                    header[3] = 0x5E.toByte()

                    sequenceNumber++
                    header[4] = (sequenceNumber ushr 24).toByte()
                    header[5] = (sequenceNumber ushr 16).toByte()
                    header[6] = (sequenceNumber ushr 8).toByte()
                    header[7] = sequenceNumber.toByte()

                    val ts = System.currentTimeMillis()
                    header[8] = (ts ushr 24).toByte()
                    header[9] = (ts ushr 16).toByte()
                    header[10] = (ts ushr 8).toByte()
                    header[11] = ts.toByte()

                    header[12] = 1.toByte() // Codec MJPEG = 1

                    val size = jpegBytes.size
                    header[16] = (size ushr 24).toByte()
                    header[17] = (size ushr 16).toByte()
                    header[18] = (size ushr 8).toByte()
                    header[19] = size.toByte()

                    synchronized(this) {
                        outStream.write(header)
                        outStream.write(jpegBytes)
                        outStream.flush()
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopNativeCameraStream() {
        if (!isStreamingNative) return
        isStreamingNative = false
        System.out.println("[*] Stopping native camera stream...")

        stopAudioCapture()

        try {
            captureSession?.close()
            captureSession = null
            cameraDevice?.close()
            cameraDevice = null
            imageReader?.close()
            imageReader = null
            
            outputStream?.close()
            outputStream = null
            socket?.close()
            socket = null
            
            cameraHandlerThread?.quitSafely()
            cameraHandlerThread = null
            cameraHandler = null
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun startAudioCapture() {
        if (isStreamingAudio) return
        isStreamingAudio = true

        val sampleRate = 48000
        val channelConfig = AudioFormat.CHANNEL_IN_MONO
        val audioFormat = AudioFormat.ENCODING_PCM_16BIT
        val bufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)

        if (bufferSize <= 0) {
            System.err.println("[!] Invalid AudioRecord buffer size: $bufferSize")
            return
        }

        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                channelConfig,
                audioFormat,
                bufferSize
            )

            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                System.err.println("[!] Failed to initialize AudioRecord")
                audioRecord?.release()
                audioRecord = null
                return
            }

            audioRecord?.startRecording()
            System.out.println("[+] AudioRecord started recording.")

            audioThread = Thread {
                val audioBuffer = ByteArray(bufferSize)
                while (isStreamingAudio && isStreamingNative) {
                    val readBytes = audioRecord?.read(audioBuffer, 0, audioBuffer.size) ?: -1
                    if (readBytes > 0) {
                        sendAudioPacket(audioBuffer, readBytes)
                    }
                }
            }
            audioThread?.start()
        } catch (e: SecurityException) {
            System.err.println("[!] Permission RECORD_AUDIO not granted or audio device busy.")
            e.printStackTrace()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopAudioCapture() {
        isStreamingAudio = false
        try {
            audioRecord?.stop()
            audioRecord?.release()
            audioRecord = null
            audioThread?.join(1000)
            audioThread = null
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun sendAudioPacket(buffer: ByteArray, size: Int) {
        socketExecutor.submit {
            try {
                val out = outputStream ?: return@submit
                val header = ByteArray(20)

                header[0] = 0xCA.toByte()
                header[1] = 0x5E.toByte()
                header[2] = 0xCA.toByte()
                header[3] = 0x5E.toByte()

                sequenceNumber++
                header[4] = (sequenceNumber ushr 24).toByte()
                header[5] = (sequenceNumber ushr 16).toByte()
                header[6] = (sequenceNumber ushr 8).toByte()
                header[7] = sequenceNumber.toByte()

                val ts = System.currentTimeMillis()
                header[8] = (ts ushr 24).toByte()
                header[9] = (ts ushr 16).toByte()
                header[10] = (ts ushr 8).toByte()
                header[11] = ts.toByte()

                header[12] = 10.toByte() // Codec PCM Audio = 10

                header[16] = (size ushr 24).toByte()
                header[17] = (size ushr 16).toByte()
                header[18] = (size ushr 8).toByte()
                header[19] = size.toByte()

                synchronized(this) {
                    out.write(header)
                    out.write(buffer, 0, size)
                    out.flush()
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun getSupportedResolutions(): List<Map<String, Any>> {
        val list = mutableListOf<Map<String, Any>>()
        try {
            val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val cameraId = cameraManager.cameraIdList.firstOrNull { id ->
                val chars = cameraManager.getCameraCharacteristics(id)
                chars.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
            } ?: cameraManager.cameraIdList[0]

            val chars = cameraManager.getCameraCharacteristics(cameraId)
            val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            if (map != null) {
                val sizes = map.getOutputSizes(ImageFormat.JPEG)
                if (sizes != null) {
                    val bestSizes = mutableMapOf<Int, android.util.Size>()
                    for (size in sizes) {
                        val h = size.height
                        // Filter hanya tinggi standar streaming video (4K/2160p, 2K/1440p, 1080p, 720p, 480p, 360p)
                        if (h == 2160 || h == 1440 || h == 1080 || h == 720 || h == 480 || h == 360) {
                            val currentBest = bestSizes[h]
                            if (currentBest == null) {
                                bestSizes[h] = size
                            } else {
                                // Pilih rasio aspek yang paling mendekati 16:9 widescreen
                                val currentAspect = currentBest.width.toFloat() / currentBest.height.toFloat()
                                val newAspect = size.width.toFloat() / size.height.toFloat()
                                val currentDiff = Math.abs(currentAspect - 1.7777778f)
                                val newDiff = Math.abs(newAspect - 1.7777778f)
                                if (newDiff < currentDiff) {
                                    bestSizes[h] = size
                                }
                            }
                        }
                    }

                    // Urutkan tinggi dari terbesar ke terkecil
                    val sortedSizes = bestSizes.values.sortedByDescending { it.height }

                    for (size in sortedSizes) {
                        val minDuration = map.getOutputMinFrameDuration(ImageFormat.JPEG, size)
                        val maxFps = if (minDuration > 0) {
                            (1_000_000_000L / minDuration).toInt()
                        } else {
                            30
                        }
                        
                        val displayFps = if (maxFps >= 60) 60 else if (maxFps >= 30) 30 else maxFps

                        val item = mapOf(
                            "width" to size.width,
                            "height" to size.height,
                            "maxFps" to displayFps
                        )
                        list.add(item)
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return list
    }

    override fun onDestroy() {
        stopNativeCameraStream()
        super.onDestroy()
    }
}
