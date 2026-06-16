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
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat

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
    @Volatile private var isStreamingNative = false
    private val isSendingFrame = java.util.concurrent.atomic.AtomicBoolean(false)
    private var cameraCloseLatch: CountDownLatch? = null
    
    private var isStreamingAudio = false
    private var audioRecord: AudioRecord? = null
    private var audioThread: Thread? = null
    
    private var cameraHandlerThread: HandlerThread? = null
    private var cameraHandler: Handler? = null

    private var activeCodec = 1 // 1 = MJPEG, 2 = H264
    private var activeWidth = 1280
    private var activeHeight = 720
    private val sessionVersion = java.util.concurrent.atomic.AtomicInteger(0)
    private var mediaCodec: MediaCodec? = null
    private var mediaCodecThread: Thread? = null
    private var encoderSurface: Surface? = null
    
    private var useFrontCamera = false
    private var flashEnabled = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CONTROL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startCapture" -> {
                    val ip = call.argument<String>("ip") ?: "127.0.0.1"
                    val port = call.argument<Int>("port") ?: 4455
                    val codec = call.argument<Int>("codec") ?: 1
                    val width = call.argument<Int>("width") ?: 1280
                    val height = call.argument<Int>("height") ?: 720
                    val enableAudio = call.argument<Boolean>("enableAudio") ?: false

                    startNativeCameraStream(ip, port, codec, width, height, enableAudio)
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
                "switchCamera" -> {
                    val useFront = call.argument<Boolean>("useFront") ?: false
                    setCameraLens(useFront)
                    result.success(null)
                }
                "toggleFlash" -> {
                    val enable = call.argument<Boolean>("enable") ?: false
                    setFlash(enable)
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun startNativeCameraStream(ip: String, port: Int, codec: Int, width: Int, height: Int, enableAudio: Boolean) {
        if (isStreamingNative) return
        isStreamingNative = true
        val currentSession = sessionVersion.incrementAndGet()
        activeCodec = codec
        activeWidth = width
        activeHeight = height
        sequenceNumber = 0

        if (cameraHandlerThread == null) {
            cameraHandlerThread = HandlerThread("CameraHandlerThread").apply { start() }
            cameraHandler = Handler(cameraHandlerThread!!.looper)
        }

        socketExecutor.submit {
            try {
                // Tunggu kamera sebelumnya benar-benar selesai dirilis
                val latch = cameraCloseLatch
                if (latch != null) {
                    System.out.println("[*] Menunggu kamera sebelumnya dirilis...")
                    latch.await(3, TimeUnit.SECONDS)
                    cameraCloseLatch = null
                }

                System.out.println("[*] Connecting native socket to $ip:$port...")
                socket = Socket(ip, port).apply {
                    tcpNoDelay = true
                    sendBufferSize = 1024 * 1024 // 1 MB Buffer
                }
                outputStream = socket!!.getOutputStream()
                System.out.println("[+] Socket connected! Initializing native camera...")

                mainHandler.post {
                    initNativeCamera(width, height, currentSession)
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

    private fun calculateBitrate(width: Int, height: Int): Int {
        val pixels = width * height
        return when {
            pixels >= 3840 * 2160 -> 24_000_000 // 4K
            pixels >= 2560 * 1440 -> 14_000_000 // 2K/1440p
            pixels >= 1920 * 1080 -> 8_000_000  // 1080p
            pixels >= 1280 * 720  -> 4_000_000  // 720p
            else -> 2_000_000                  // 480p / 360p
        }
    }

    private fun initNativeCamera(width: Int, height: Int, version: Int) {
        try {
            val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val targetLens = if (useFrontCamera) CameraCharacteristics.LENS_FACING_FRONT else CameraCharacteristics.LENS_FACING_BACK
            val cameraId = cameraManager.cameraIdList.firstOrNull { id ->
                val chars = cameraManager.getCameraCharacteristics(id)
                chars.get(CameraCharacteristics.LENS_FACING) == targetLens
            } ?: cameraManager.cameraIdList[0]

            System.out.println("[Debug] initNativeCamera: ${width}x${height}, codec=${activeCodec}")

            if (activeCodec == 2) {
                val mime = MediaFormat.MIMETYPE_VIDEO_AVC
                try {
                    val tempCodec = MediaCodec.createEncoderByType(mime)
                    val encoderInfo = tempCodec.codecInfo
                    val caps = encoderInfo.getCapabilitiesForType(mime)
                    val videoCaps = caps.videoCapabilities
                    
                    if (videoCaps == null || !videoCaps.isSizeSupported(width, height)) {
                        System.out.println("[!] Encoder ${encoderInfo.name} tidak mendukung ${width}x${height}. Fallback ke MJPEG.")
                        activeCodec = 1
                    } else {
                        System.out.println("[+] Encoder ${encoderInfo.name} mendukung ${width}x${height}")
                    }
                    tempCodec.release()
                } catch (e: Exception) {
                    System.out.println("[!] Gagal cek kapabilitas encoder: ${e.message}. Fallback ke MJPEG.")
                    activeCodec = 1
                }
            }

            var cameraSurface: Surface? = null
            if (activeCodec == 2) {
                try {
                    // Inisialisasi H264 MediaCodec hardware encoder
                    // Gunakan dimensi kamera apa adanya (portrait/landscape)
                    val mime = MediaFormat.MIMETYPE_VIDEO_AVC
                    val format = MediaFormat.createVideoFormat(mime, width, height).apply {
                        setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
                        setInteger(MediaFormat.KEY_BIT_RATE, calculateBitrate(width, height))
                        setInteger(MediaFormat.KEY_FRAME_RATE, 30)
                        setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
                        try { setInteger(MediaFormat.KEY_LATENCY, 1) } catch (e: Exception) {}
                        try { setInteger(MediaFormat.KEY_PRIORITY, 0) } catch (e: Exception) {}
                    }
                    
                    mediaCodec = MediaCodec.createEncoderByType(mime).apply {
                        configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                    }
                    encoderSurface = mediaCodec!!.createInputSurface()
                    cameraSurface = encoderSurface!!
                    System.out.println("[+] H264 encoder berhasil dikonfigurasi: ${width}x${height}")

                    // Thread pembaca output bitstream H264
                    mediaCodecThread = Thread {
                        val bufferInfo = MediaCodec.BufferInfo()
                        try {
                            mediaCodec!!.start()
                            while (isStreamingNative && activeCodec == 2 && version == sessionVersion.get()) {
                                val outputBufferIndex = mediaCodec!!.dequeueOutputBuffer(bufferInfo, 10000)
                                if (outputBufferIndex >= 0) {
                                    val outputBuffer = mediaCodec!!.getOutputBuffer(outputBufferIndex)
                                    if (outputBuffer != null) {
                                        outputBuffer.position(bufferInfo.offset)
                                        outputBuffer.limit(bufferInfo.offset + bufferInfo.size)
                                        val bytes = ByteArray(bufferInfo.size)
                                        outputBuffer.get(bytes)
                                        sendH264Packet(bytes, bufferInfo.presentationTimeUs / 1000, version)
                                    }
                                    mediaCodec!!.releaseOutputBuffer(outputBufferIndex, false)
                                }
                            }
                        } catch (e: Exception) {
                            e.printStackTrace()
                        }
                    }
                    mediaCodecThread?.start()
                } catch (e: Exception) {
                    System.err.println("[!] Gagal menginisialisasi H264: ${e.message}. Melakukan fallback ke MJPEG...")
                    e.printStackTrace()
                    activeCodec = 1
                    try {
                        mediaCodec?.stop()
                    } catch (ex: Exception) {}
                    try {
                        mediaCodec?.release()
                    } catch (ex: Exception) {}
                    mediaCodec = null
                    encoderSurface = null
                }
            }

            if (activeCodec == 1) {
                // MJPEG Mode (Fallback / Default)
                imageReader = ImageReader.newInstance(width, height, ImageFormat.JPEG, 5)
                imageReader?.setOnImageAvailableListener({ reader ->
                    val image = reader.acquireNextImage() ?: return@setOnImageAvailableListener
                    if (!isStreamingNative || version != sessionVersion.get()) {
                        image.close()
                        return@setOnImageAvailableListener
                    }

                    if (isSendingFrame.compareAndSet(false, true)) {
                        try {
                            val planes = image.planes
                            if (planes.isNotEmpty()) {
                                val buffer = planes[0].buffer
                                val size = buffer.remaining()
                                val jpegBytes = ByteArray(size)
                                buffer.get(jpegBytes)
                                image.close()

                                socketExecutor.submit {
                                    if (version == sessionVersion.get()) {
                                        try {
                                            sendFrameSync(jpegBytes, version)
                                        } finally {
                                            isSendingFrame.set(false)
                                        }
                                    } else {
                                        isSendingFrame.set(false)
                                    }
                                }
                            } else {
                                image.close()
                                isSendingFrame.set(false)
                            }
                        } catch (e: Exception) {
                            e.printStackTrace()
                            image.close()
                            isSendingFrame.set(false)
                        }
                    } else {
                        image.close()
                    }
                }, cameraHandler)
                cameraSurface = imageReader!!.surface
            }

            if (cameraSurface == null) {
                throw Exception("Camera output Surface is null")
            }

            cameraManager.openCamera(cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    cameraDevice = camera
                    startNativeCaptureSession(cameraSurface)
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

    private fun startNativeCaptureSession(cameraSurface: Surface) {
        val outputs = listOf(cameraSurface)
        
        cameraDevice?.createCaptureSession(outputs, object : CameraCaptureSession.StateCallback() {
            override fun onConfigured(session: CameraCaptureSession) {
                captureSession = session
                try {
                    val builder = cameraDevice!!.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
                    builder.addTarget(cameraSurface)

                    // Enable high quality temporal noise reduction and disable edge enhancement to avoid amplifying noise
                    try { builder.set(CaptureRequest.NOISE_REDUCTION_MODE, CaptureRequest.NOISE_REDUCTION_MODE_HIGH_QUALITY) } catch (e: Exception) {}
                    try { builder.set(CaptureRequest.EDGE_MODE, CaptureRequest.EDGE_MODE_OFF) } catch (e: Exception) {}
                    try { builder.set(CaptureRequest.COLOR_CORRECTION_ABERRATION_MODE, CaptureRequest.COLOR_CORRECTION_ABERRATION_MODE_HIGH_QUALITY) } catch (e: Exception) {}
                    try { builder.set(CaptureRequest.HOT_PIXEL_MODE, CaptureRequest.HOT_PIXEL_MODE_HIGH_QUALITY) } catch (e: Exception) {}
                    try { builder.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON) } catch (e: Exception) {}
                    
                    // Flash Mode
                    if (flashEnabled) {
                        try { builder.set(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_TORCH) } catch (e: Exception) {}
                    } else {
                        try { builder.set(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_OFF) } catch (e: Exception) {}
                    }

                    // Konfigurasi target FPS range untuk mengaktifkan 30 FPS jika didukung
                    val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
                    val cameraId = cameraDevice?.id ?: "0"
                    val chars = cameraManager.getCameraCharacteristics(cameraId)
                    val fpsRanges = chars.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
                    if (fpsRanges != null) {
                        var bestRange: android.util.Range<Int>? = null
                        for (range in fpsRanges) {
                            if (range.upper == 30) {
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

    private fun sendFrameSync(jpegBytes: ByteArray, version: Int) {
        if (version != sessionVersion.get()) return
        try {
            val outStream = outputStream ?: return
            val header = ByteArray(24)
            
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
            header[13] = if (useFrontCamera) 1.toByte() else 0.toByte()

            // Tulis metadata Lebar dan Tinggi ke Header (Byte 14-15 dan 16-17)
            header[14] = (activeWidth ushr 8).toByte()
            header[15] = activeWidth.toByte()
            header[16] = (activeHeight ushr 8).toByte()
            header[17] = activeHeight.toByte()

            val size = jpegBytes.size
            header[20] = (size ushr 24).toByte()
            header[21] = (size ushr 16).toByte()
            header[22] = (size ushr 8).toByte()
            header[23] = size.toByte()

            synchronized(this) {
                outStream.write(header)
                outStream.write(jpegBytes)
                outStream.flush()
            }
        } catch (e: java.net.SocketException) {
            System.err.println("[!] Socket error saat kirim MJPEG: ${e.message}")
            mainHandler.post { stopNativeCameraStream() }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopNativeCameraStream() {
        if (!isStreamingNative) return
        isStreamingNative = false
        System.out.println("[*] Stopping native camera stream...")

        stopAudioCapture()

        // Siapkan latch untuk sinkronisasi penutupan kamera
        val latch = CountDownLatch(1)
        cameraCloseLatch = latch

        try {
            captureSession?.close()
            captureSession = null
        } catch (e: Exception) { e.printStackTrace() }

        val cam = cameraDevice
        if (cam != null) {
            try {
                cam.close()
            } catch (e: Exception) { e.printStackTrace() }
            cameraDevice = null
        }

        try {
            mediaCodec?.stop()
        } catch (e: Exception) {}
        try {
            mediaCodec?.release()
        } catch (e: Exception) {}
        mediaCodec = null

        try {
            mediaCodecThread?.join(1000)
        } catch (e: Exception) {}
        mediaCodecThread = null
        encoderSurface = null

        try {
            imageReader?.close()
        } catch (e: Exception) {}
        imageReader = null

        try {
            outputStream?.close()
        } catch (e: Exception) {}
        outputStream = null
        try {
            socket?.close()
        } catch (e: Exception) {}
        socket = null

        // Reset isSendingFrame agar tidak memblokir sesi berikutnya
        isSendingFrame.set(false)

        // Beri waktu kamera & encoder untuk release sepenuhnya, lalu buka latch
        Thread {
            Thread.sleep(500)
            latch.countDown()
            System.out.println("[+] Native camera stream stopped & resources released.")
        }.start()
    }

    private fun sendH264Packet(h264Bytes: ByteArray, ptsMs: Long, version: Int) {
        try {
            if (version != sessionVersion.get()) return
            socketExecutor.submit {
                try {
                    if (version != sessionVersion.get()) return@submit
                    val outStream = outputStream ?: return@submit
                    val header = ByteArray(24)
                    
                    header[0] = 0xCA.toByte()
                    header[1] = 0x5E.toByte()
                    header[2] = 0xCA.toByte()
                    header[3] = 0x5E.toByte()

                    sequenceNumber++
                    header[4] = (sequenceNumber ushr 24).toByte()
                    header[5] = (sequenceNumber ushr 16).toByte()
                    header[6] = (sequenceNumber ushr 8).toByte()
                    header[7] = sequenceNumber.toByte()

                    header[8] = (ptsMs ushr 24).toByte()
                    header[9] = (ptsMs ushr 16).toByte()
                    header[10] = (ptsMs ushr 8).toByte()
                    header[11] = ptsMs.toByte()

                    header[12] = 2.toByte() // Codec H264 = 2
                    header[13] = if (useFrontCamera) 1.toByte() else 0.toByte()

                    // Tulis metadata Lebar dan Tinggi ke Header (Byte 14-15 dan 16-17)
                    header[14] = (activeWidth ushr 8).toByte()
                    header[15] = activeWidth.toByte()
                    header[16] = (activeHeight ushr 8).toByte()
                    header[17] = activeHeight.toByte()

                    val size = h264Bytes.size
                    header[20] = (size ushr 24).toByte()
                    header[21] = (size ushr 16).toByte()
                    header[22] = (size ushr 8).toByte()
                    header[23] = size.toByte()

                    synchronized(this) {
                        outStream.write(header)
                        outStream.write(h264Bytes)
                        outStream.flush()
                    }
                } catch (e: java.net.SocketException) {
                    System.err.println("[!] Socket error saat kirim H264: ${e.message}")
                    mainHandler.post { stopNativeCameraStream() }
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
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
                        val chunk = ByteArray(readBytes)
                        System.arraycopy(audioBuffer, 0, chunk, 0, readBytes)
                        sendAudioPacket(chunk, readBytes)
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
                val header = ByteArray(24)

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

                header[20] = (size ushr 24).toByte()
                header[21] = (size ushr 16).toByte()
                header[22] = (size ushr 8).toByte()
                header[23] = size.toByte()

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

    private fun isResolutionSupported(width: Int, height: Int): Boolean {
        try {
            val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val cameraId = cameraManager.cameraIdList.firstOrNull { id ->
                val chars = cameraManager.getCameraCharacteristics(id)
                chars.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
            } ?: cameraManager.cameraIdList[0]

            val chars = cameraManager.getCameraCharacteristics(cameraId)
            val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            if (map != null) {
                val sizes = map.getOutputSizes(ImageFormat.JPEG) ?: emptyArray()
                val cameraSupports = sizes.any { it.width == width && it.height == height }
                if (!cameraSupports) return false
            }

            val codecList = MediaCodecList(MediaCodecList.REGULAR_CODECS)
            for (info in codecList.codecInfos) {
                if (!info.isEncoder) continue
                for (type in info.supportedTypes) {
                    if (type.equals(MediaFormat.MIMETYPE_VIDEO_AVC, ignoreCase = true)) {
                        val caps = info.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC)
                        val videoCaps = caps?.videoCapabilities
                        if (videoCaps != null) {
                            if (videoCaps.isSizeSupported(width, height)) {
                                return true
                            }
                        }
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return false
    }

    private fun getSupportedResolutions(): List<Map<String, Any>> {
        val list = mutableListOf<Map<String, Any>>()
        val targets = listOf(
            android.util.Size(848, 480),
            android.util.Size(1280, 720),
            android.util.Size(1920, 1080),
            android.util.Size(1920, 1440),
            android.util.Size(2560, 1440),
            android.util.Size(3840, 2160)
        )

        for (target in targets) {
            val supported = isResolutionSupported(target.width, target.height)
            list.add(mapOf(
                "width" to target.width,
                "height" to target.height,
                "maxFps" to 30,
                "supported" to supported
            ))
        }
        return list
    }

    private fun setCameraLens(useFront: Boolean) {
        if (useFrontCamera == useFront) return
        useFrontCamera = useFront
        if (isStreamingNative) {
            mainHandler.post {
                val currentSession = sessionVersion.get()
                // Stop camera & session
                try { captureSession?.close(); captureSession = null } catch(e: Exception){}
                try { cameraDevice?.close(); cameraDevice = null } catch(e: Exception){}
                try { imageReader?.close(); imageReader = null } catch(e: Exception){}
                // Re-open camera with the new lens direction
                initNativeCamera(activeWidth, activeHeight, currentSession)
            }
        }
    }

    private fun setFlash(enable: Boolean) {
        if (flashEnabled == enable) return
        flashEnabled = enable
        if (isStreamingNative) {
            mainHandler.post {
                try {
                    val session = captureSession ?: return@post
                    val builder = cameraDevice?.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW) ?: return@post
                    
                    if (activeCodec == 2) {
                        val surf = encoderSurface ?: return@post
                        builder.addTarget(surf)
                    } else {
                        val reader = imageReader ?: return@post
                        builder.addTarget(reader.surface)
                    }
                    
                    try { builder.set(CaptureRequest.NOISE_REDUCTION_MODE, CaptureRequest.NOISE_REDUCTION_MODE_HIGH_QUALITY) } catch (e: Exception) {}
                    try { builder.set(CaptureRequest.EDGE_MODE, CaptureRequest.EDGE_MODE_OFF) } catch (e: Exception) {}
                    try { builder.set(CaptureRequest.COLOR_CORRECTION_ABERRATION_MODE, CaptureRequest.COLOR_CORRECTION_ABERRATION_MODE_HIGH_QUALITY) } catch (e: Exception) {}
                    try { builder.set(CaptureRequest.HOT_PIXEL_MODE, CaptureRequest.HOT_PIXEL_MODE_HIGH_QUALITY) } catch (e: Exception) {}
                    try { builder.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON) } catch (e: Exception) {}
                    
                    if (flashEnabled) {
                        builder.set(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_TORCH)
                    } else {
                        builder.set(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_OFF)
                    }
                    
                    session.setRepeatingRequest(builder.build(), null, cameraHandler)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
    }

    override fun onDestroy() {
        stopNativeCameraStream()
        cameraHandlerThread?.quitSafely()
        cameraHandlerThread = null
        cameraHandler = null
        super.onDestroy()
    }
}
