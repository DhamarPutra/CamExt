#pragma once
#include "i_decoder.h"
#include <windows.h>
#include <mfapi.h>
#include <mftransform.h>

class WMFH264Decoder : public IDecoder {
public:
    WMFH264Decoder();
    ~WMFH264Decoder() override;

    bool Decode(
        const uint8_t* compressed_data,
        size_t compressed_size,
        uint8_t* output_buffer,
        size_t& output_size,
        int& out_width,
        int& out_height,
        bool is_front = false
    ) override;

private:
    bool InitializeMF(int width, int height);
    void CleanupMF();

    IMFTransform* pDecoderMFT_ = nullptr;
    bool is_initialized_ = false;
    int width_ = 0;
    int height_ = 0;
    int requested_width_ = 0;
    int requested_height_ = 0;
};
