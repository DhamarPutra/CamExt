#include "socket_server.h"
#include <iostream>
#include <vector>

#ifdef _WIN32
    #pragma comment(lib, "ws2_32.lib")
#else
    #include <sys/socket.h>
    #include <netinet/in.h>
    #include <unistd.h>
    #include <fcntl.h>
#endif

SocketServer::SocketServer(FrameQueue& queue)
    : queue_(queue), port_(0), use_tcp_(true), is_running_(false),
      server_fd_(INVALID_SOCKET), client_fd_(INVALID_SOCKET) {}

SocketServer::~SocketServer() {
    Stop();
}

bool SocketServer::InitializeSockets() {
#ifdef _WIN32
    WSADATA wsa;
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
        return false;
    }
#endif
    return true;
}

void SocketServer::CleanupSockets() {
#ifdef _WIN32
    WSACleanup();
#endif
}

bool SocketServer::Start(int port, bool use_tcp) {
    if (is_running_) return false;

    if (!InitializeSockets()) return false;

    port_ = port;
    use_tcp_ = use_tcp;
    is_running_ = true;

    if (use_tcp_) {
        worker_thread_ = std::thread(&SocketServer::RunTcpServer, this);
    } else {
        worker_thread_ = std::thread(&SocketServer::RunUdpServer, this);
    }

    return true;
}

void SocketServer::Stop() {
    if (!is_running_) return;
    is_running_ = false;

    // Tutup socket paksa untuk membangunkan thread pendengar yang terblokir
#ifdef _WIN32
    if (server_fd_ != INVALID_SOCKET) closesocket(server_fd_);
    if (client_fd_ != INVALID_SOCKET) closesocket(client_fd_);
#else
    if (server_fd_ != INVALID_SOCKET) ::close(server_fd_);
    if (client_fd_ != INVALID_SOCKET) ::close(client_fd_);
#endif

    server_fd_ = INVALID_SOCKET;
    client_fd_ = INVALID_SOCKET;

    if (worker_thread_.joinable()) {
        worker_thread_.join();
    }

    CleanupSockets();
}

void SocketServer::RunTcpServer() {
    server_fd_ = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (server_fd_ == INVALID_SOCKET) {
        is_running_ = false;
        return;
    }

    // Set reusable port
    int opt = 1;
    setsockopt(server_fd_, SOL_SOCKET, SO_REUSEADDR, reinterpret_cast<const char*>(&opt), sizeof(opt));

    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port_);

    if (bind(server_fd_, reinterpret_cast<sockaddr*>(&address), sizeof(address)) < 0) {
        Stop();
        return;
    }

    if (listen(server_fd_, 1) < 0) {
        Stop();
        return;
    }

    PacketDemuxer demuxer;
    std::vector<uint8_t> recv_buffer(65536);

    while (is_running_) {
        sockaddr_in client_addr{};
#ifdef _WIN32
        int addr_len = sizeof(client_addr);
#else
        socklen_t addr_len = sizeof(client_addr);
#endif
        client_fd_ = accept(server_fd_, reinterpret_cast<sockaddr*>(&client_addr), &addr_len);
        if (client_fd_ == INVALID_SOCKET) {
            break;
        }

        // Set TCP No Delay untuk latensi ultra-rendah
        int nodelay = 1;
        setsockopt(client_fd_, IPPROTO_TCP, TCP_NODELAY, reinterpret_cast<const char*>(&nodelay), sizeof(nodelay));

        demuxer.Reset();

        while (is_running_) {
            int bytes_read = recv(client_fd_, reinterpret_cast<char*>(recv_buffer.data()), static_cast<int>(recv_buffer.size()), 0);
            if (bytes_read <= 0) {
                // Koneksi ditutup oleh HP atau terjadi kesalahan
                break;
            }

            demuxer.FeedData(recv_buffer.data(), bytes_read);

            FramePacket packet;
            while (demuxer.ParseNextPacket(packet)) {
                queue_.Push(std::move(packet));
            }
        }

#ifdef _WIN32
        closesocket(client_fd_);
#else
        ::close(client_fd_);
#endif
        client_fd_ = INVALID_SOCKET;
    }
}

void SocketServer::RunUdpServer() {
    server_fd_ = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (server_fd_ == INVALID_SOCKET) {
        is_running_ = false;
        return;
    }

    // Naikkan ukuran receive buffer socket UDP untuk mencegah frame drop di tingkat OS
    int rcvbuf_size = 4 * 1024 * 1024; // 4 MB
    setsockopt(server_fd_, SOL_SOCKET, SO_RCVBUF, reinterpret_cast<const char*>(&rcvbuf_size), sizeof(rcvbuf_size));

    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port_);

    if (bind(server_fd_, reinterpret_cast<sockaddr*>(&address), sizeof(address)) < 0) {
        Stop();
        return;
    }

    PacketDemuxer demuxer;
    std::vector<uint8_t> recv_buffer(65536);

    while (is_running_) {
        sockaddr_in client_addr{};
#ifdef _WIN32
        int addr_len = sizeof(client_addr);
#else
        socklen_t addr_len = sizeof(client_addr);
#endif
        int bytes_read = recvfrom(server_fd_, reinterpret_cast<char*>(recv_buffer.data()), static_cast<int>(recv_buffer.size()), 0,
                                  reinterpret_cast<sockaddr*>(&client_addr), &addr_len);
        if (bytes_read <= 0) {
            break;
        }

        demuxer.FeedData(recv_buffer.data(), bytes_read);

        FramePacket packet;
        while (demuxer.ParseNextPacket(packet)) {
            queue_.Push(std::move(packet));
        }
    }
}
