#pragma once

#include <cstdint>
#include <cstddef>

enum class CodecType : uint8_t {
    MJPEG = 1,
    H264 = 2,
    H265 = 3,
    PCM_AUDIO = 10
};

class IDecoder {
public:
    virtual ~IDecoder() = default;

    /// Decodes a compressed video slice into raw YUV420p or BGRA buffer.
    /// @param compressed_data Pointer to the incoming compressed slice.
    /// @param compressed_size Size of the compressed slice.
    /// @param output_buffer Pre-allocated target output buffer.
    /// @param output_size Size of output buffer (in/out: sets raw frame size).
    /// @param out_width Output width of decoded frame.
    /// @param out_height Output height of decoded frame.
    /// @return True if decoding succeeds, false otherwise.
    virtual bool Decode(
        const uint8_t* compressed_data,
        size_t compressed_size,
        uint8_t* output_buffer,
        size_t& output_size,
        int& out_width,
        int& out_height
    ) = 0;
};
