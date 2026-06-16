#include "wic_jpeg_decoder.h"
#include <shlwapi.h>
#include <iostream>

#pragma comment(lib, "Windowscodecs.lib")
#pragma comment(lib, "Shlwapi.lib")

WICJPEGDecoder::WICJPEGDecoder() {
    CoInitializeEx(NULL, COINIT_MULTITHREADED);
    HRESULT hr = CoCreateInstance(
        CLSID_WICImagingFactory,
        NULL,
        CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&pFactory_)
    );
    if (FAILED(hr)) {
        std::cerr << "[WIC Decoder] Gagal membuat WIC Imaging Factory! HRESULT: 0x" << std::hex << hr << std::dec << std::endl;
    }
}

WICJPEGDecoder::~WICJPEGDecoder() {
    if (pFactory_) {
        pFactory_->Release();
        pFactory_ = nullptr;
    }
    CoUninitialize();
}

bool WICJPEGDecoder::Decode(
    const uint8_t* compressed_data,
    size_t compressed_size,
    uint8_t* output_buffer,
    size_t& output_size,
    int& out_width,
    int& out_height,
    bool is_front
) {
    if (!pFactory_ || !compressed_data || compressed_size == 0) return false;

    IStream* pStream = SHCreateMemStream(compressed_data, static_cast<UINT>(compressed_size));
    if (!pStream) return false;

    IWICBitmapDecoder* pDecoder = nullptr;
    HRESULT hr = pFactory_->CreateDecoderFromStream(pStream, NULL, WICDecodeMetadataCacheOnDemand, &pDecoder);
    pStream->Release();
    if (FAILED(hr)) {
        return false;
    }

    IWICBitmapFrameDecode* pFrame = nullptr;
    hr = pDecoder->GetFrame(0, &pFrame);
    if (FAILED(hr)) {
        pDecoder->Release();
        return false;
    }

    IWICFormatConverter* pConverter = nullptr;
    hr = pFactory_->CreateFormatConverter(&pConverter);
    if (FAILED(hr)) {
        pFrame->Release();
        pDecoder->Release();
        return false;
    }

    // Rotasi 90 derajat secara native via WIC Flip Rotator (ditambah Flip Vertikal jika kamera depan)
    IWICBitmapSource* pSource = pFrame;
    IWICBitmapFlipRotator* pRotator = nullptr;
    if (SUCCEEDED(pFactory_->CreateBitmapFlipRotator(&pRotator))) {
        WICBitmapTransformOptions options = WICBitmapTransformRotate90;
        if (is_front) {
            options = static_cast<WICBitmapTransformOptions>(WICBitmapTransformRotate90 | WICBitmapTransformFlipVertical);
        }
        if (SUCCEEDED(pRotator->Initialize(pFrame, options))) {
            pSource = pRotator;
        }
    }

    // Ubah format piksel warna JPEG mentah ke BGRA 32-bit
    hr = pConverter->Initialize(
        pSource,
        GUID_WICPixelFormat32bppBGRA,
        WICBitmapDitherTypeNone,
        NULL,
        0.0f,
        WICBitmapPaletteTypeCustom
    );

    bool success = false;
    if (SUCCEEDED(hr)) {
        UINT width = 0, height = 0;
        pConverter->GetSize(&width, &height);

        UINT stride = width * 4;
        size_t required_size = stride * height;

        if (output_size >= required_size) {
            hr = pConverter->CopyPixels(NULL, stride, static_cast<UINT>(output_size), output_buffer);
            if (SUCCEEDED(hr)) {
                out_width = static_cast<int>(width);
                out_height = static_cast<int>(height);
                output_size = required_size;
                success = true;
            }
        }
    }

    if (pRotator) {
        pRotator->Release();
    }
    pConverter->Release();
    pFrame->Release();
    pDecoder->Release();

    return success;
}
