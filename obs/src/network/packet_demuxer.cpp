#include "packet_demuxer.h"
#include <cstring>
#include <algorithm>

// Helper to parse 32-bit Big-Endian uint
static uint32_t ParseUint32BE(const uint8_t* ptr) {
    return (static_cast<uint32_t>(ptr[0]) << 24) |
           (static_cast<uint32_t>(ptr[1]) << 16) |
           (static_cast<uint32_t>(ptr[2]) << 8)  |
           (static_cast<uint32_t>(ptr[3]));
}

void PacketDemuxer::FeedData(const uint8_t* data, size_t size) {
    if (size == 0 || data == nullptr) return;
    buffer_.insert(buffer_.end(), data, data + size);
}

bool PacketDemuxer::ParseNextPacket(FramePacket& out_packet) {
    while (buffer_.size() >= HEADER_SIZE) {
        // 1. Sinkronisasi Stream: Cari Magic Header 0xCA5ECA5E
        uint32_t magic = ParseUint32BE(buffer_.data());
        if (magic != MAGIC_HEADER) {
            // Hilangkan 1 byte pertama dan teruskan pencarian
            buffer_.erase(buffer_.begin());
            continue;
        }

        // 2. Baca Ukuran Payload (Byte ke 20 - 23)
        uint32_t payload_size = ParseUint32BE(buffer_.data() + 20);
        size_t total_packet_size = HEADER_SIZE + payload_size;

        // 3. Pastikan seluruh paket payload telah terakumulasi di buffer
        if (buffer_.size() < total_packet_size) {
            // Data belum lengkap, tunggu feed data berikutnya
            return false;
        }

        // 4. Ekstraksi Metadata Header
        out_packet.sequence = ParseUint32BE(buffer_.data() + 4);
        out_packet.timestamp = ParseUint32BE(buffer_.data() + 8);
        out_packet.codec = static_cast<CodecType>(buffer_.data()[12]);
        out_packet.is_front = (buffer_.data()[13] == 1);

        // Ekstraksi 16-bit Lebar dan Tinggi (Byte 14-15 dan 16-17)
        out_packet.width = (static_cast<uint16_t>(buffer_.data()[14]) << 8) | buffer_.data()[15];
        out_packet.height = (static_cast<uint16_t>(buffer_.data()[16]) << 8) | buffer_.data()[17];

        // 5. Salin Payload Terkompresi
        out_packet.payload.resize(payload_size);
        std::memcpy(out_packet.payload.data(), buffer_.data() + HEADER_SIZE, payload_size);

        // 6. Bersihkan paket yang sudah diproses dari buffer internal
        buffer_.erase(buffer_.begin(), buffer_.begin() + total_packet_size);
        return true;
    }

    return false;
}

void PacketDemuxer::Reset() {
    buffer_.clear();
}
