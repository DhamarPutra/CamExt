#include <obs-module.h>
#include <obs.h>
#include <util/platform.h>
#include <atomic>
#include <thread>
#include <vector>
#include "network/socket_server.h"
#include "utils/frame_queue.h"
#include "decoder/i_decoder.h"

// Placeholder for concrete decoder headers
// In future phases, these will be replaced with real libjpeg-turbo & FFmpeg decoders
class MockDecoder : public IDecoder {
public:
    bool Decode(const uint8_t* compressed_data, size_t compressed_size, 
                uint8_t* output_buffer, size_t& output_size, int& out_width, int& out_height) override {
        // Mock decoding: just copy/pass dummy visual buffer or return a mock frame
        out_width = 1920;
        out_height = 1080;
        
        // Simulasikan output YUV420p mentah (1.5 * width * height)
        size_t required_size = (1920 * 1080 * 3) / 2;
        if (output_size < required_size) {
            output_size = required_size;
            return false;
        }
        output_size = required_size;

        // Isi Y (Luminance) dengan data terkompresi tiruan agar ada bayangan visual saat testing
        std::memset(output_buffer, 0x80, 1920 * 1080); // Gray luminance
        std::memset(output_buffer + (1920 * 1080), 0x80, (1920 * 1080) / 2); // Chroma neutral

        return true;
    }
};

struct CamExtSource {
    obs_source_t* source;
    FrameQueue queue;
    SocketServer server;
    
    std::thread decode_thread;
    std::atomic<bool> is_decoding;
    IDecoder* decoder;

    int port;
    bool use_tcp;
    CodecType codec;

    CamExtSource(obs_source_t* src) 
        : source(src), queue(3), server(queue), is_decoding(false), decoder(nullptr),
          port(4455), use_tcp(true), codec(CodecType::H264) {
        decoder = new MockDecoder();
    }

    ~CamExtSource() {
        Stop();
        delete decoder;
    }

    void Start() {
        if (is_decoding) return;
        is_decoding = true;

        server.Start(port, use_tcp);
        decode_thread = std::thread(&CamExtSource::DecodeLoop, this);
    }

    void Stop() {
        if (!is_decoding) return;
        is_decoding = false;

        server.Stop();
        queue.Shutdown();

        if (decode_thread.joinable()) {
            decode_thread.join();
        }
        queue.Clear();
    }

    void DecodeLoop() {
        std::vector<uint8_t> raw_buffer(1920 * 1080 * 3); // Cukup besar untuk frame 1080p YUV420p
        FramePacket packet;

        while (is_decoding) {
            if (!queue.Pop(packet, 100)) {
                continue;
            }

            size_t out_size = raw_buffer.size();
            int width = 0;
            int height = 0;

            if (decoder->Decode(packet.payload.data(), packet.payload.size(), 
                                raw_buffer.data(), out_size, width, height)) {
                
                // Siapkan struct frame OBS Studio
                obs_source_frame obs_frame{};
                obs_frame.data[0] = raw_buffer.data();                                      // Plane Y
                obs_frame.data[1] = raw_buffer.data() + (width * height);                  // Plane U
                obs_frame.data[2] = raw_buffer.data() + (width * height) + (width * height / 4); // Plane V
                
                obs_frame.linesize[0] = width;
                obs_frame.linesize[1] = width / 2;
                obs_frame.linesize[2] = width / 2;
                
                obs_frame.width = width;
                obs_frame.height = height;
                obs_frame.format = VIDEO_FORMAT_I420; // YUV420p
                obs_frame.timestamp = static_cast<uint64_t>(packet.timestamp) * 1000; // Mikrodetik ke Nanodetik

                // Salurkan ke pipeline rendering OBS
                obs_source_output_video(source, &obs_frame);
            }
        }
    }
};

// --- OBS CALLBACKS IMPLEMENTATION ---

static const char* camext_get_name(void*) {
    return "CamExt Video Receiver";
}

static void* camext_create(obs_data_t* settings, obs_source_t* source) {
    auto* context = new CamExtSource(source);
    
    // Ambil pengaturan awal dari OBS
    context->port = static_cast<int>(obs_data_get_int(settings, "port"));
    if (context->port == 0) context->port = 4455;
    
    context->use_tcp = obs_data_get_bool(settings, "use_tcp");
    context->codec = static_cast<CodecType>(obs_data_get_int(settings, "codec"));

    context->Start();
    return context;
}

static void camext_destroy(void* data) {
    auto* context = static_cast<CamExtSource*>(data);
    delete context;
}

static obs_properties_t* camext_get_properties(void* data) {
    obs_properties_t* props = obs_properties_create();

    obs_properties_add_int(props, "port", "Port Soket", 1024, 65535, 1);
    
    obs_property_t* proto_prop = obs_properties_add_list(
        props, "use_tcp", "Protokol", OBS_COMBO_TYPE_LIST, OBS_COMBO_FORMAT_INT);
    obs_property_list_add_int(proto_prop, "TCP (Stabil)", 1);
    obs_property_list_add_int(proto_prop, "UDP (Cepat)", 0);

    obs_property_t* codec_prop = obs_properties_add_list(
        props, "codec", "Pilihan Codec", OBS_COMBO_TYPE_LIST, OBS_COMBO_FORMAT_INT);
    obs_property_list_add_int(codec_prop, "H.264 (Standard)", 2);
    obs_property_list_add_int(codec_prop, "H.265 (Bandwidth Saving)", 3);
    obs_property_list_add_int(codec_prop, "MJPEG (Zero Latency)", 1);

    return props;
}

static void camext_update(void* data, obs_data_t* settings) {
    auto* context = static_cast<CamExtSource*>(data);
    context->Stop();

    context->port = static_cast<int>(obs_data_get_int(settings, "port"));
    context->use_tcp = obs_data_get_bool(settings, "use_tcp");
    context->codec = static_cast<CodecType>(obs_data_get_int(settings, "codec"));

    context->Start();
}

OBS_DECLARE_MODULE()
OBS_MODULE_USE_DEFAULT_LOCALE("camext", "en-US")

bool obs_module_load(void) {
    obs_source_info info{};
    info.id = "camext_source";
    info.type = OBS_SOURCE_TYPE_INPUT;
    info.output_flags = OBS_SOURCE_VIDEO;
    info.get_name = camext_get_name;
    info.create = camext_create;
    info.destroy = camext_destroy;
    info.get_properties = camext_get_properties;
    info.update = camext_update;
    info.icon_type = OBS_ICON_TYPE_CAMERA;

    obs_register_source(&info);
    return true;
}
