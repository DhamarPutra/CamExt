#pragma once

#include <string>
#include <thread>
#include <atomic>
#include "packet_demuxer.h"
#include "../utils/frame_queue.h"

// Platform-independent socket handles
#ifdef _WIN32
    #include <winsock2.h>
    #include <ws2tcpip.h>
    typedef SOCKET SocketHandle;
#else
    #define INVALID_SOCKET -1
    typedef int SocketHandle;
#endif

class SocketServer {
public:
    SocketServer(FrameQueue& video_queue, FrameQueue* audio_queue = nullptr);
    ~SocketServer();

    /// Starts the async socket listener on the specified port.
    bool Start(int port, bool use_tcp);

    /// Stops the socket listener and shuts down worker threads.
    void Stop();

    bool IsRunning() const { return is_running_; }

private:
    void RunTcpServer();
    void RunUdpServer();
    bool InitializeSockets();
    void CleanupSockets();

    FrameQueue& video_queue_;
    FrameQueue* audio_queue_;
    int port_;
    bool use_tcp_;
    std::atomic<bool> is_running_;
    std::thread worker_thread_;

    SocketHandle server_fd_;
    SocketHandle client_fd_;
};
