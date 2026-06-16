#include "network/socket_server.h"
#include <windows.h>
#include <wincodec.h>
#include <shlwapi.h>
#include <mmsystem.h>
#include <iostream>
#include <chrono>
#include <vector>
#include <thread>
#include <atomic>
#include "utils/frame_queue.h"
#include "decoder/wmf_h264_decoder.h"

#pragma comment(lib, "Windowscodecs.lib")
#pragma comment(lib, "Shlwapi.lib")
#pragma comment(lib, "winmm.lib")

// Dimensi visualizer default
const int WINDOW_WIDTH = 640;
const int WINDOW_HEIGHT = 480;

// Audio Playback global handle
HWAVEOUT g_hWaveOut = nullptr;

void CALLBACK WaveCallback(HWAVEOUT hwo, UINT uMsg, DWORD_PTR dwInstance, DWORD_PTR dwParam1, DWORD_PTR dwParam2) {
    if (uMsg == WOM_DONE) {
        WAVEHDR* pHeader = reinterpret_cast<WAVEHDR*>(dwParam1);
        waveOutUnprepareHeader(hwo, pHeader, sizeof(WAVEHDR));
        if (pHeader->lpData) {
            delete[] pHeader->lpData;
        }
        delete pHeader;
    }
}

void InitializeAudioPlayback() {
    WAVEFORMATEX wfx;
    wfx.wFormatTag = WAVE_FORMAT_PCM;
    wfx.nChannels = 1; // Mono
    wfx.nSamplesPerSec = 48000; // 48kHz
    wfx.wBitsPerSample = 16; // 16-bit
    wfx.nBlockAlign = (wfx.nChannels * wfx.wBitsPerSample) / 8;
    wfx.nAvgBytesPerSec = wfx.nSamplesPerSec * wfx.nBlockAlign;
    wfx.cbSize = 0;

    MMRESULT result = waveOutOpen(&g_hWaveOut, WAVE_MAPPER, &wfx, reinterpret_cast<DWORD_PTR>(WaveCallback), 0, CALLBACK_FUNCTION);
    if (result != MMSYSERR_NOERROR) {
        std::cerr << "[Audio Error] Gagal membuka waveOut device! Code: " << result << std::endl;
    } else {
        std::cout << "[Audio] waveOut playback berhasil diinisialisasi (48kHz Mono 16-bit)." << std::endl;
    }
}

void PlayAudioBuffer(const uint8_t* data, size_t size) {
    if (!g_hWaveOut || size == 0) return;

    WAVEHDR* pHeader = new WAVEHDR();
    ZeroMemory(pHeader, sizeof(WAVEHDR));
    
    pHeader->lpData = new char[size];
    std::memcpy(pHeader->lpData, data, size);
    pHeader->dwBufferLength = static_cast<DWORD>(size);

    MMRESULT res = waveOutPrepareHeader(g_hWaveOut, pHeader, sizeof(WAVEHDR));
    if (res == MMSYSERR_NOERROR) {
        res = waveOutWrite(g_hWaveOut, pHeader, sizeof(WAVEHDR));
        if (res != MMSYSERR_NOERROR) {
            waveOutUnprepareHeader(g_hWaveOut, pHeader, sizeof(WAVEHDR));
            delete[] pHeader->lpData;
            delete pHeader;
        }
    } else {
        delete[] pHeader->lpData;
        delete pHeader;
    }
}

// Mutex & Buffer global untuk pertukaran data video ke GUI Thread
std::vector<uint8_t> g_rgb_buffer;
int g_frame_width = 0;
int g_frame_height = 0;
CRITICAL_SECTION g_buffer_cs;

// Status penutupan aplikasi
std::atomic<bool> g_app_running(true);
HWND g_hwnd = NULL;

// Callback fungsi Jendela Win32
LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_PAINT: {
            PAINTSTRUCT ps;
            HDC hdc = BeginPaint(hwnd, &ps);

            EnterCriticalSection(&g_buffer_cs);
            if (!g_rgb_buffer.empty() && g_frame_width > 0 && g_frame_height > 0) {
                // Konfigurasi struktur data piksel Bitmap (Windows DIB mengharapkan BGRA32)
                BITMAPINFO bmi = {0};
                bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
                bmi.bmiHeader.biWidth = g_frame_width;
                bmi.bmiHeader.biHeight = -g_frame_height; // Negatif agar render dari atas ke bawah
                bmi.bmiHeader.biPlanes = 1;
                bmi.bmiHeader.biBitCount = 32; // BGRA 32-bit
                bmi.bmiHeader.biCompression = BI_RGB;

                // Dapatkan ukuran area client jendela saat ini
                RECT rect;
                GetClientRect(hwnd, &rect);
                int win_w = rect.right - rect.left;
                int win_h = rect.bottom - rect.top;

                // Hitung aspek rasio agar gambar tidak penyet / meregang (nge-wide)
                float frame_aspect = (float)g_frame_width / (float)g_frame_height;
                float win_aspect = (float)win_w / (float)win_h;

                int dest_x = 0;
                int dest_y = 0;
                int dest_w = win_w;
                int dest_h = win_h;

                if (win_aspect > frame_aspect) {
                    // Jendela terlalu lebar, tambahkan pillarbox (area hitam di kiri & kanan)
                    dest_w = (int)(win_h * frame_aspect);
                    dest_x = (win_w - dest_w) / 2;
                } else {
                    // Jendela terlalu tinggi, tambahkan letterbox (area hitam di atas & bawah)
                    dest_h = (int)(win_w / frame_aspect);
                    dest_y = (win_h - dest_h) / 2;
                }

                // Bersihkan margin saja (pillarbox / letterbox) untuk mencegah sisa-sisa gambar (ghosting) tanpa menyebabkan flicker!
                HBRUSH bgBrush = CreateSolidBrush(RGB(18, 18, 18));
                if (dest_x > 0) {
                    // Pillarbox: bersihkan area kiri & kanan
                    RECT left_margin = { 0, 0, dest_x, win_h };
                    RECT right_margin = { dest_x + dest_w, 0, win_w, win_h };
                    FillRect(hdc, &left_margin, bgBrush);
                    FillRect(hdc, &right_margin, bgBrush);
                }
                if (dest_y > 0) {
                    // Letterbox: bersihkan area atas & bawah
                    RECT top_margin = { 0, 0, win_w, dest_y };
                    RECT bottom_margin = { 0, dest_y + dest_h, win_w, win_h };
                    FillRect(hdc, &top_margin, bgBrush);
                    FillRect(hdc, &bottom_margin, bgBrush);
                }
                DeleteObject(bgBrush);

                // Blit performa tinggi dengan penskalaan aspek rasio yang tepat
                SetStretchBltMode(hdc, COLORONCOLOR);
                StretchDIBits(
                    hdc,
                    dest_x, dest_y, dest_w, dest_h,      // Area Jendela Tujuan yang Pas
                    0, 0, g_frame_width, g_frame_height, // Ukuran Data Frame Asli
                    g_rgb_buffer.data(),
                    &bmi,
                    DIB_RGB_COLORS,
                    SRCCOPY
                );
            } else {
                // Tampilkan Teks Menunggu saat belum ada frame masuk
                RECT rect;
                GetClientRect(hwnd, &rect);
                SetTextColor(hdc, RGB(255, 255, 255));
                SetBkColor(hdc, RGB(18, 18, 18));
                DrawTextA(hdc, "Menunggu koneksi kamera dari HP...", -1, &rect, DT_CENTER | DT_SINGLELINE | DT_VCENTER);
            }
            LeaveCriticalSection(&g_buffer_cs);

            EndPaint(hwnd, &ps);
            return 0;
        }
        case WM_ERASEBKGND:
            return 1; // Bypass background erase untuk mencegah flicker
        case WM_CLOSE:
            g_app_running = false;
            DestroyWindow(hwnd);
            return 0;
        case WM_DESTROY:
            PostQuitMessage(0);
            return 0;
        default:
            return DefWindowProc(hwnd, msg, wParam, lParam);
    }
}

// WIC JPEG Decoder is now handled by the WICJPEGDecoder class.

#include "decoder/wic_jpeg_decoder.h"

void ResizeWindowToFrame(HWND hwnd, int width, int height) {
    if (!hwnd) return;

    // Dapatkan ukuran monitor utama
    int screenWidth = GetSystemMetrics(SM_CXSCREEN);
    int screenHeight = GetSystemMetrics(SM_CYSCREEN);

    // Tentukan ukuran maksimal area client (80% dari resolusi layar)
    int maxClientWidth = (screenWidth * 8) / 10;
    int maxClientHeight = (screenHeight * 8) / 10;

    int destWidth = width;
    int destHeight = height;

    float aspect = (float)width / (float)height;
    if (destWidth > maxClientWidth) {
        destWidth = maxClientWidth;
        destHeight = (int)(destWidth / aspect);
    }
    if (destHeight > maxClientHeight) {
        destHeight = maxClientHeight;
        destWidth = (int)(destHeight * aspect);
    }

    DWORD style = GetWindowLong(hwnd, GWL_STYLE);
    DWORD exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);
    HMENU menu = GetMenu(hwnd);

    RECT rect = {0, 0, destWidth, destHeight};
    AdjustWindowRectEx(&rect, style, menu != nullptr, exStyle);

    int winWidth = rect.right - rect.left;
    int winHeight = rect.bottom - rect.top;

    int posX = (screenWidth - winWidth) / 2;
    int posY = (screenHeight - winHeight) / 2;
    if (posX < 0) posX = 0;
    if (posY < 0) posY = 0;

    SetWindowPos(hwnd, NULL, posX, posY, winWidth, winHeight, SWP_NOZORDER | SWP_NOACTIVATE);
}

// Thread khusus untuk menerima paket socket dan mendekode frame secara non-blocking
void NetworkReceiveLoop(FrameQueue* queue, SocketServer* server) {
    FramePacket packet;
    int frame_count = 0;
    auto last_time = std::chrono::steady_clock::now();

    std::vector<uint8_t> decoded_bgr;
    int width = 0, height = 0;

    while (g_app_running && server->IsRunning()) {
        if (queue->Pop(packet, 100)) {
            frame_count++;

            // Hitung statistik FPS ke konsol setiap 60 frame
            if (frame_count % 60 == 0) {
                auto now = std::chrono::steady_clock::now();
                std::chrono::duration<double> elapsed = now - last_time;
                double fps = 60.0 / elapsed.count();
                std::cout << "[Stats] FPS Kamera HP: " << fps << std::endl;
                last_time = now;
            }

            bool decode_success = false;
            width = packet.width;
            height = packet.height;

            if (packet.codec == CodecType::H264) {
                static WMFH264Decoder h264_decoder;
                size_t out_size = decoded_bgr.capacity();
                if (out_size < static_cast<size_t>(width * height * 4)) {
                    decoded_bgr.resize(width * height * 4);
                }
                out_size = decoded_bgr.size();
                decode_success = h264_decoder.Decode(packet.payload.data(), packet.payload.size(), decoded_bgr.data(), out_size, width, height, packet.is_front);
            } else {
                static WICJPEGDecoder jpeg_decoder;
                size_t out_size = decoded_bgr.capacity();
                if (out_size < static_cast<size_t>(width * height * 4)) {
                    decoded_bgr.resize(width * height * 4);
                }
                out_size = decoded_bgr.size();
                decode_success = jpeg_decoder.Decode(packet.payload.data(), packet.payload.size(), decoded_bgr.data(), out_size, width, height, packet.is_front);
            }

            if (decode_success) {
                static int last_width = 0;
                static int last_height = 0;
                if (width != last_width || height != last_height) {
                    std::cout << "[Debug] Konfigurasi Kamera Aktif: " << width << "x" << height 
                              << " (Codec: " << (packet.codec == CodecType::H264 ? "H.264" : "MJPEG") << ")" << std::endl;
                    last_width = width;
                    last_height = height;
                    
                    // Lakukan resize window agar sesuai aspect ratio frame
                    ResizeWindowToFrame(g_hwnd, width, height);
                }

                // Salin secara aman ke buffer GUI utama
                EnterCriticalSection(&g_buffer_cs);
                g_rgb_buffer = std::move(decoded_bgr);
                g_frame_width = width;
                g_frame_height = height;
                LeaveCriticalSection(&g_buffer_cs);

                // Minta OS Windows melakukan pembaruan cat jendela (repainting)
                if (g_hwnd) {
                    InvalidateRect(g_hwnd, NULL, FALSE);
                }
            } else {
                // Jika dekode gagal (mungkin paket belum lengkap saat buffering awal)
                // Kita biarkan frame sebelumnya tetap tayang agar tidak berkedip hitam
            }
        }
    }
}

void AudioReceiveLoop(FrameQueue* audio_queue) {
    FramePacket packet;
    while (g_app_running) {
        if (audio_queue->Pop(packet, 100)) {
            PlayAudioBuffer(packet.payload.data(), packet.payload.size());
        }
    }
}

int main() {
    std::cout << "===========================================" << std::endl;
    std::cout << "    CamExt Standalone GPU Visualizer       " << std::endl;
    std::cout << "===========================================" << std::endl;

    InitializeCriticalSection(&g_buffer_cs);
    InitializeAudioPlayback();

    FrameQueue queue(5);
    FrameQueue audio_queue(100);
    SocketServer server(queue, &audio_queue);

    int port = 4455;
    bool use_tcp = true;

    std::cout << "[*] Memulai server soket di port " << port << "..." << std::endl;
    if (!server.Start(port, use_tcp)) {
        std::cerr << "[Error] Gagal memulai server soket!" << std::endl;
        if (g_hWaveOut) {
            waveOutClose(g_hWaveOut);
        }
        DeleteCriticalSection(&g_buffer_cs);
        return 1;
    }

    std::cout << "[+] Server berjalan. Membuat jendela visualizer..." << std::endl;

    // --- PEMBUATAN WINDOWS GUI NATIVE (WIN32 API) ---
    HINSTANCE hInstance = GetModuleHandle(NULL);
    WNDCLASSEX wc = {0};
    wc.cbSize = sizeof(WNDCLASSEX);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInstance;
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    wc.lpszClassName = L"CamExtVisualizerClass";

    if (!RegisterClassEx(&wc)) {
        std::cerr << "[Error] Gagal mendaftarkan kelas Window!" << std::endl;
        server.Stop();
        if (g_hWaveOut) {
            waveOutClose(g_hWaveOut);
        }
        DeleteCriticalSection(&g_buffer_cs);
        return 1;
    }

    // Buat jendela di tengah layar monitor
    g_hwnd = CreateWindowEx(
        0,
        L"CamExtVisualizerClass",
        L"CamExt - Live Camera Screen",
        WS_OVERLAPPEDWINDOW | WS_VISIBLE,
        CW_USEDEFAULT, CW_USEDEFAULT, WINDOW_WIDTH, WINDOW_HEIGHT,
        NULL, NULL, hInstance, NULL
    );

    if (!g_hwnd) {
        std::cerr << "[Error] Gagal membuat Window GUI!" << std::endl;
        server.Stop();
        if (g_hWaveOut) {
            waveOutClose(g_hWaveOut);
        }
        DeleteCriticalSection(&g_buffer_cs);
        return 1;
    }

    // Set background warna gelap modern (Aesthetic Dark Mode)
    HBRUSH brush = CreateSolidBrush(RGB(18, 18, 18));
    SetClassLongPtr(g_hwnd, GCLP_HBRBACKGROUND, (LONG_PTR)brush);

    // Jalankan thread penerimaan soket video dan audio
    std::thread net_thread(NetworkReceiveLoop, &queue, &server);
    std::thread audio_thread(AudioReceiveLoop, &audio_queue);

    // --- WINDOWS MESSAGE LOOP (MAIN THREAD) ---
    MSG msg;
    while (g_app_running) {
        if (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
            if (msg.message == WM_QUIT) {
                g_app_running = false;
            }
        } else {
            std::this_thread::sleep_for(std::chrono::milliseconds(2));
        }
    }

    std::cout << "[*] Membersihkan resource..." << std::endl;
    
    server.Stop();

    if (net_thread.joinable()) {
        net_thread.join();
    }
    if (audio_thread.joinable()) {
        audio_thread.join();
    }

    if (g_hWaveOut) {
        waveOutReset(g_hWaveOut);
        waveOutClose(g_hWaveOut);
        g_hWaveOut = nullptr;
    }

    DeleteObject(brush);
    DeleteCriticalSection(&g_buffer_cs);
    
    std::cout << "[+] Selesai. Aplikasi ditutup." << std::endl;
    return 0;
}
