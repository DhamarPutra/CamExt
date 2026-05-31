#pragma once

#include <vector>
#include <cstdint>
#include <cstddef>
#include "../decoder/i_decoder.h"

struct FramePacket {
    uint32_t sequence;
    uint32_t timestamp;
    CodecType codec;
    std::vector<uint8_t> payload;
};

class PacketDemuxer {
public:
    PacketDemuxer() = default;
    ~PacketDemuxer() = default;

    /// Appends incoming socket chunk bytes to internal stream buffer.
    void FeedData(const uint8_t* data, size_t size);

    /// Statefully parses the stream to extract the next complete frame packet.
    /// @param out_packet Populated with extracted frame details if returns true.
    /// @return True if a complete packet is successfully parsed and extracted.
    bool ParseNextPacket(FramePacket& out_packet);

    /// Clears any accumulated data from the internal buffer.
    void Reset();

private:
    std::vector<uint8_t> buffer_;
    static const uint32_t MAGIC_HEADER = 0xCA5ECA5E;
    static const size_t HEADER_SIZE = 20;
};
