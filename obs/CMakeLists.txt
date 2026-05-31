cmake_minimum_required(VERSION 3.15)
project(camext LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Tentukan direktori output plugin agar siap disalin ke folder plugins OBS Studio
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

# --- DETEKSI DEPENDENSI & SDK ---

# Pilihan path SDK eksternal untuk Windows (diarahkan ke obs-sdk lokal kita agar instan)
set(OBS_SDK_PATH "${CMAKE_CURRENT_SOURCE_DIR}/obs-sdk" CACHE PATH "Path to OBS Studio SDK")

set(HAS_OBS OFF)

if(OBS_SDK_PATH AND EXISTS "${OBS_SDK_PATH}/include")
    include_directories(${OBS_SDK_PATH}/include)
    link_directories(${OBS_SDK_PATH}/win64)
    message(STATUS "Menggunakan OBS SDK dari: ${OBS_SDK_PATH}")
    set(HAS_OBS ON)
else()
    # Deteksi standar via pkg-config atau CMake Modules secara opsional
    find_package(libobs QUIET)
    if(libobs_FOUND)
        set(HAS_OBS ON)
        message(STATUS "libobs berhasil ditemukan!")
    else()
        message(WARNING "libobs tidak ditemukan! Target DLL plugin 'camext' dilewati. Hanya target standalone 'camext_receiver' yang akan dibangun.")
    endif()
endif()

# Dependensi tambahan untuk Decoder (akan digunakan pada perluasan implementasi)
# find_package(FFmpeg REQUIRED COMPONENTS avcodec avutil)
# find_package(libjpeg-turbo REQUIRED)

# --- TARGET KOMPILASI PLUGIN ---

if(HAS_OBS)
    add_library(camext SHARED
        src/obs-plugin-main.cpp
        src/network/packet_demuxer.h
        src/network/packet_demuxer.cpp
        src/network/socket_server.h
        src/network/socket_server.cpp
        src/decoder/i_decoder.h
        src/utils/frame_queue.h
    )

    # Konfigurasi include path internal
    target_include_directories(camext PRIVATE
        src
    )

    # Tautkan library OBS Studio
    if(OBS_SDK_PATH)
        target_link_libraries(camext PRIVATE obs)
    else()
        target_link_libraries(camext PRIVATE libobs)
    endif()

    # Tambahkan pustaka Socket khusus untuk Windows (Winsock)
    if(WIN32)
        target_link_libraries(camext PRIVATE ws2_32)
        # Atur definisi unicode & fungsi Windows
        target_compile_definitions(camext PRIVATE _UNICODE UNICODE _CRT_SECURE_NO_WARNINGS)
    endif()

    # Set penamaan prefix keluaran agar bersih (misal camext.dll bukan libcamext.dll di Windows)
    set_target_properties(camext PROPERTIES
        PREFIX ""
        SUFFIX ${CMAKE_SHARED_LIBRARY_SUFFIX}
    )
endif()

# --- TARGET EXECUTABLE MANDIRI (STANDALONE RECEIVER) ---
add_executable(camext_receiver
    src/receiver-main.cpp
    src/network/packet_demuxer.h
    src/network/packet_demuxer.cpp
    src/network/socket_server.h
    src/network/socket_server.cpp
    src/decoder/i_decoder.h
    src/utils/frame_queue.h
)

target_include_directories(camext_receiver PRIVATE src)

if(WIN32)
    target_link_libraries(camext_receiver PRIVATE ws2_32)
    target_compile_definitions(camext_receiver PRIVATE _UNICODE UNICODE _CRT_SECURE_NO_WARNINGS)
endif()

