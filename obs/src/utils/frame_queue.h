#pragma once

#include <queue>
#include <mutex>
#include <condition_variable>
#include "../network/packet_demuxer.h"

class FrameQueue {
public:
    explicit FrameQueue(size_t max_capacity = 3) 
        : max_capacity_(max_capacity), cleared_(false) {}

    ~FrameQueue() {
        Shutdown();
    }

    /// Pushes a new frame packet. If capacity is exceeded, drops the oldest frame.
    void Push(FramePacket&& packet) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (cleared_) return;

        // Latency Discipline: Drop oldest frame if queue exceeds capacity
        if (queue_.size() >= max_capacity_) {
            queue_.pop(); // Discard the oldest frame to preserve latency bounds
        }

        queue_.push(std::move(packet));
        cond_var_.notify_one();
    }

    /// Pops a frame packet. Blocks until one is available or timeout is reached.
    bool Pop(FramePacket& out_packet, int timeout_ms = 100) {
        std::unique_lock<std::mutex> lock(mutex_);
        
        bool success = cond_var_.wait_for(lock, std::chrono::milliseconds(timeout_ms), [this]() {
            return !queue_.empty() || cleared_;
        });

        if (!success || queue_.empty() || cleared_) {
            return false;
        }

        out_packet = std::move(queue_.front());
        queue_.pop();
        return true;
    }

    void Clear() {
        std::lock_guard<std::mutex> lock(mutex_);
        std::queue<FramePacket> empty_queue;
        std::swap(queue_, empty_queue);
    }

    void Shutdown() {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            cleared_ = true;
        }
        cond_var_.notify_all();
    }

private:
    size_t max_capacity_;
    std::queue<FramePacket> queue_;
    std::mutex mutex_;
    std::condition_variable cond_var_;
    bool cleared_;
};
