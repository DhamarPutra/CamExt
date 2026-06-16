#pragma once
#include "i_decoder.h"
#include <windows.h>
#include <wincodec.h>

class WICJPEGDecoder : public IDecoder {
public:
    WICJPEGDecoder();
    ~WICJPEGDecoder() override;

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
    IWICImagingFactory* pFactory_ = nullptr;
};
