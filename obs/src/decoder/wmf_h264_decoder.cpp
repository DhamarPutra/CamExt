#include "wmf_h264_decoder.h"
#include <iostream>
#include <mferror.h>
#include <wmcodecdsp.h>

#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "Ole32.lib")
#pragma comment(lib, "wmcodecdspuuid.lib")

// Helper: Convert NV12 to BGR24 WITH 90-degree clockwise rotation (portrait→landscape)
// Input: width×height (portrait, e.g. 1080×1920) → Output: height×width (landscape, e.g. 1920×1080)
static void NV12ToBGR24_Rotate90CW(const uint8_t* nv12, int nv12_stride, uint8_t* bgr, int in_width, int in_height) {
    const uint8_t* yPlane = nv12;
    const uint8_t* uvPlane = nv12 + (nv12_stride * in_height);
    
    // Output dimensions after 90° CW rotation
    int out_width = in_height;
    int out_height = in_width;
    int bgrStride = out_width * 3;

    for (int out_y = 0; out_y < out_height; ++out_y) {
        for (int out_x = 0; out_x < out_width; ++out_x) {
            // Map rotated output pixel back to input pixel
            // 90° CW: input(x, y) → output(in_height-1-y, x)
            // Inverse: output(out_x, out_y) → input(out_y, in_height-1-out_x)
            int in_x = out_y;
            int in_y = in_height - 1 - out_x;

            int yIndex = in_y * nv12_stride + in_x;
            int uvIndex = (in_y / 2) * nv12_stride + (in_x & ~1);

            uint8_t Y = yPlane[yIndex];
            uint8_t U = uvPlane[uvIndex];
            uint8_t V = uvPlane[uvIndex + 1];

            int c = Y - 16;
            int d = U - 128;
            int e = V - 128;

            int r = (298 * c + 409 * e + 128) >> 8;
            int g = (298 * c - 100 * d - 208 * e + 128) >> 8;
            int b = (298 * c + 516 * d + 128) >> 8;

            r = (r < 0) ? 0 : ((r > 255) ? 255 : r);
            g = (g < 0) ? 0 : ((g > 255) ? 255 : g);
            b = (b < 0) ? 0 : ((b > 255) ? 255 : b);

            int bgrIndex = out_y * bgrStride + out_x * 3;
            bgr[bgrIndex] = static_cast<uint8_t>(b);
            bgr[bgrIndex + 1] = static_cast<uint8_t>(g);
            bgr[bgrIndex + 2] = static_cast<uint8_t>(r);
        }
    }
}

WMFH264Decoder::WMFH264Decoder() {
    CoInitializeEx(NULL, COINIT_MULTITHREADED);
    MFStartup(MF_VERSION);
}

WMFH264Decoder::~WMFH264Decoder() {
    CleanupMF();
    MFShutdown();
    CoUninitialize();
}

void WMFH264Decoder::CleanupMF() {
    if (pDecoderMFT_) {
        pDecoderMFT_->Release();
        pDecoderMFT_ = nullptr;
    }
    is_initialized_ = false;
}

bool WMFH264Decoder::InitializeMF(int width, int height) {
    CleanupMF();

    std::cout << "[WMF Decoder] Initializing MFT for " << width << "x" << height << std::endl;

    HRESULT hr = CoCreateInstance(CLSID_CMSH264DecoderMFT, NULL, CLSCTX_INPROC_SERVER,
                                  IID_IMFTransform, (void**)&pDecoderMFT_);
    if (FAILED(hr)) {
        std::cerr << "[WMF Decoder] Gagal membuat H264 Decoder MFT. HR: 0x" << std::hex << hr << std::dec << std::endl;
        return false;
    }

    // Enable low-latency mode if available
    IMFAttributes* pAttributes = nullptr;
    hr = pDecoderMFT_->GetAttributes(&pAttributes);
    if (SUCCEEDED(hr) && pAttributes) {
        pAttributes->SetUINT32(MF_LOW_LATENCY, TRUE);
        pAttributes->Release();
    }

    // Configure Input Media Type
    IMFMediaType* pInputType = nullptr;
    hr = MFCreateMediaType(&pInputType);
    if (SUCCEEDED(hr)) {
        pInputType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
        pInputType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
        hr = MFSetAttributeSize(pInputType, MF_MT_FRAME_SIZE, width, height);
        if (SUCCEEDED(hr)) {
            hr = pDecoderMFT_->SetInputType(0, pInputType, 0);
        }
        pInputType->Release();
    }
    if (FAILED(hr)) {
        std::cerr << "[WMF Decoder] Gagal SetInputType. HR: 0x" << std::hex << hr << std::dec << std::endl;
        return false;
    }

    // Configure Output Media Type (NV12)
    IMFMediaType* pOutputType = nullptr;
    hr = MFCreateMediaType(&pOutputType);
    if (SUCCEEDED(hr)) {
        pOutputType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
        pOutputType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12);
        hr = MFSetAttributeSize(pOutputType, MF_MT_FRAME_SIZE, width, height);
        if (SUCCEEDED(hr)) {
            hr = pDecoderMFT_->SetOutputType(0, pOutputType, 0);
        }
        pOutputType->Release();
    }
    if (FAILED(hr)) {
        std::cerr << "[WMF Decoder] Gagal SetOutputType. HR: 0x" << std::hex << hr << std::dec << std::endl;
        return false;
    }

    pDecoderMFT_->ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0);
    pDecoderMFT_->ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0);
    
    width_ = width;
    height_ = height;
    is_initialized_ = true;
    std::cout << "[WMF Decoder] MFT berhasil diinisialisasi: " << width << "x" << height << std::endl;
    return true;
}

bool WMFH264Decoder::Decode(
    const uint8_t* compressed_data,
    size_t compressed_size,
    uint8_t* output_buffer,
    size_t& output_size,
    int& out_width,
    int& out_height
) {
    if (!is_initialized_ || out_width != width_ || out_height != height_) {
        if (!InitializeMF(out_width, out_height)) {
            return false;
        }
    }

    // Wrap compressed bitstream inside IMFMediaBuffer
    IMFMediaBuffer* pInputBuffer = nullptr;
    HRESULT hr = MFCreateMemoryBuffer(static_cast<DWORD>(compressed_size), &pInputBuffer);
    if (FAILED(hr)) return false;

    BYTE* pData = nullptr;
    hr = pInputBuffer->Lock(&pData, nullptr, nullptr);
    if (SUCCEEDED(hr)) {
        std::memcpy(pData, compressed_data, compressed_size);
        pInputBuffer->Unlock();
        pInputBuffer->SetCurrentLength(static_cast<DWORD>(compressed_size));
    } else {
        pInputBuffer->Release();
        return false;
    }

    IMFSample* pInputSample = nullptr;
    hr = MFCreateSample(&pInputSample);
    if (SUCCEEDED(hr)) {
        pInputSample->AddBuffer(pInputBuffer);
    }
    pInputBuffer->Release();
    if (FAILED(hr)) return false;

    // Send input to MFT decoder
    hr = pDecoderMFT_->ProcessInput(0, pInputSample, 0);
    pInputSample->Release();
    if (FAILED(hr) && hr != MF_E_NOTACCEPTING) {
        return false;
    }

    // Try to retrieve decoded output
    MFT_OUTPUT_DATA_BUFFER outputDataBuffer = {0};
    outputDataBuffer.dwStreamID = 0;
    
    MFT_OUTPUT_STREAM_INFO streamInfo = {0};
    pDecoderMFT_->GetOutputStreamInfo(0, &streamInfo);

    DWORD outBufSize = streamInfo.cbSize;
    if (outBufSize == 0) {
        int alignedWidth = (width_ + 15) & ~15;
        outBufSize = static_cast<DWORD>(alignedWidth * height_ * 3 / 2);
    }

    IMFMediaBuffer* pOutputBuffer = nullptr;
    hr = MFCreateMemoryBuffer(outBufSize, &pOutputBuffer);
    if (FAILED(hr)) return false;

    IMFSample* pOutputSample = nullptr;
    hr = MFCreateSample(&pOutputSample);
    if (SUCCEEDED(hr)) {
        pOutputSample->AddBuffer(pOutputBuffer);
    }
    pOutputBuffer->Release();
    if (FAILED(hr)) return false;

    outputDataBuffer.pSample = pOutputSample;

    DWORD dwStatus = 0;
    hr = pDecoderMFT_->ProcessOutput(0, 1, &outputDataBuffer, &dwStatus);
    
    bool success = false;

    if (hr == MF_E_TRANSFORM_STREAM_CHANGE) {
        IMFMediaType* pNewOutputType = nullptr;
        HRESULT hr2 = pDecoderMFT_->GetOutputAvailableType(0, 0, &pNewOutputType);
        if (SUCCEEDED(hr2)) {
            pDecoderMFT_->SetOutputType(0, pNewOutputType, 0);
            UINT32 newWidth = 0, newHeight = 0;
            MFGetAttributeSize(pNewOutputType, MF_MT_FRAME_SIZE, &newWidth, &newHeight);
            if (newWidth > 0 && newHeight > 0) {
                width_ = static_cast<int>(newWidth);
                height_ = static_cast<int>(newHeight);
            }
            pNewOutputType->Release();
        }
    } else if (hr == S_OK) {
        IMFMediaBuffer* pMediaBuffer = nullptr;
        hr = outputDataBuffer.pSample->GetBufferByIndex(0, &pMediaBuffer);
        if (SUCCEEDED(hr)) {
            BYTE* pOutData = nullptr;
            DWORD dwCurrentLength = 0;
            hr = pMediaBuffer->Lock(&pOutData, nullptr, &dwCurrentLength);
            if (SUCCEEDED(hr)) {
                // Determine NV12 stride (MFT may pad width to 16-byte alignment)
                int nv12_stride = width_;
                DWORD expectedNV12 = static_cast<DWORD>(width_ * height_ * 3 / 2);
                if (dwCurrentLength > expectedNV12) {
                    nv12_stride = static_cast<int>(dwCurrentLength * 2 / (height_ * 3));
                }

                // Rotate 90° CW: portrait (w×h) → landscape (h×w) to match MJPEG rotation behavior
                int rotated_w = height_;
                int rotated_h = width_;
                int target_bgr_size = rotated_w * rotated_h * 3;

                if (output_size >= static_cast<size_t>(target_bgr_size)) {
                    NV12ToBGR24_Rotate90CW(pOutData, nv12_stride, output_buffer, width_, height_);
                    output_size = target_bgr_size;
                    out_width = rotated_w;
                    out_height = rotated_h;
                    success = true;
                }
                pMediaBuffer->Unlock();
            }
            pMediaBuffer->Release();
        }
    }
    // MF_E_TRANSFORM_NEED_MORE_INPUT is expected for SPS/PPS — not an error

    if (outputDataBuffer.pEvents) outputDataBuffer.pEvents->Release();
    pOutputSample->Release();

    return success;
}
