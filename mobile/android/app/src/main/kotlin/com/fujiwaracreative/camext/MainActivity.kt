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
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.OutputStream
import java.net.Socket
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val CONTROL_CHANNEL = "com.fujiwaracreative.camext/control"

    private val mainHandler = Handler(Looper.getMainLooper())
    private val socketExecutor = Executors.newSingleThreadExecutor()

    private var socket: Socket? = null
    private var outputStream: OutputStream? = null
    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var imageReader: ImageReader? = null
    private var sequenceNumber = 0
    private var isStreamingNative = false
    
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

                    startNativeCameraStream(ip, port, width, height)
                    result.success(null)
                }
                "stopCapture" -> {
                    stopNativeCameraStream()
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun startNativeCameraStream(ip: String, port: Int, width: Int, height: Int) {
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

            imageReader = ImageReader.newInstance(width, height, ImageFormat.YUV_420_888, 3)
            imageReader?.setOnImageAvailableListener({ reader ->
                val image = reader.acquireLatestImage()
                if (image != null) {
                    if (isStreamingNative) {
                        processAndSendFrame(image)
                    }
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
                    val builder = cameraDevice!!.createCaptureRequest(CameraDevice.TEMPLATE_RECORD)
                    builder.addTarget(readerSurface)
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

    private fun processAndSendFrame(image: Image) {
        try {
            val width = image.width
            val height = image.height
            val planes = image.planes
            val yBytes = ByteArray(planes[0].buffer.remaining()).also { planes[0].buffer.get(it) }
            val uBytes = ByteArray(planes[1].buffer.remaining()).also { planes[1].buffer.get(it) }
            val vBytes = ByteArray(planes[2].buffer.remaining()).also { planes[2].buffer.get(it) }

            val yRowStride = planes[0].rowStride
            val uRowStride = planes[1].rowStride
            val vRowStride = planes[2].rowStride
            val uPixelStride = planes[1].pixelStride
            val vPixelStride = planes[2].pixelStride

            val jpegBytes = convertYuvToJpeg(
                yBytes, uBytes, vBytes,
                yRowStride, uRowStride, vRowStride,
                uPixelStride, vPixelStride,
                width, height, 75
            )

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

                    header[12] = 1.toByte() // Codec MJPEG = 1

                    val size = jpegBytes.size
                    header[16] = (size ushr 24).toByte()
                    header[17] = (size ushr 16).toByte()
                    header[18] = (size ushr 8).toByte()
                    header[19] = size.toByte()

                    synchronized(this) {
                        out.write(header)
                        out.write(jpegBytes)
                        out.flush()
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
        stopNativeCameraStream()
        super.onDestroy()
    }
}
