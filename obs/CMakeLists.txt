cmake_minimum_required(VERSION 3.15)
project(camext LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Tentukan direktori output plugin agar siap disalin ke folder plugins OBS Studio
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

# --- DETEKSI DEPENDENSI & SDK ---
# OBS SDK checks removed.

# Dependensi tambahan untuk Decoder (akan digunakan pada perluasan implementasi)
# find_package(FFmpeg REQUIRED COMPONENTS avcodec avutil)
# find_package(libjpeg-turbo REQUIRED)

# --- TARGET COMPILATION PLUGIN REMOVED ---
# OBS Plugin camext has been disabled/removed per user request.

# --- TARGET EXECUTABLE MANDIRI (STANDALONE RECEIVER) ---
add_executable(camext_receiver
    src/receiver-main.cpp
    src/network/packet_demuxer.h
    src/network/packet_demuxer.cpp
    src/network/socket_server.h
    src/network/socket_server.cpp
    src/decoder/i_decoder.h
    src/decoder/wmf_h264_decoder.h
    src/decoder/wmf_h264_decoder.cpp
    src/decoder/wic_jpeg_decoder.h
    src/decoder/wic_jpeg_decoder.cpp
    src/utils/frame_queue.h
)

target_include_directories(camext_receiver PRIVATE src)

if(WIN32)
    target_link_libraries(camext_receiver PRIVATE ws2_32 mfplat mfuuid ole32 wmcodecdspuuid)
    target_compile_definitions(camext_receiver PRIVATE _UNICODE UNICODE _CRT_SECURE_NO_WARNINGS)
endif()

if(OpenMP_CXX_FOUND)
    target_link_libraries(camext_receiver PRIVATE OpenMP::OpenMP_CXX)
endif()

