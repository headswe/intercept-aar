#include "async_writer.hpp"

#include <chrono>

namespace aar {

bool async_writer::open(const std::string& path) {
    close();
    file_.open(path, std::ios::out | std::ios::trunc | std::ios::binary);
    if (!file_.is_open()) return false;
    stop_ = false;
    running_ = true;
    thread_ = std::thread([this] { run(); });
    return true;
}

void async_writer::write(std::string line) {
    if (!running_) return;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        pending_.emplace_back(std::move(line));
    }
    cv_.notify_one();
}

void async_writer::close() {
    if (!running_) return;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        stop_ = true;
    }
    cv_.notify_one();
    if (thread_.joinable()) thread_.join();
    file_.close();
    running_ = false;
}

void async_writer::run() {
    std::vector<std::string> batch;
    for (;;) {
        bool stopping;
        {
            std::unique_lock<std::mutex> lock(mutex_);
            // Wake on new data, on stop, or every second so a crash loses at most ~1s.
            cv_.wait_for(lock, std::chrono::seconds(1), [this] { return stop_ || !pending_.empty(); });
            batch.swap(pending_);
            stopping = stop_;
        }
        for (const auto& line : batch) file_ << line;
        batch.clear();
        file_.flush();
        if (stopping) {
            std::lock_guard<std::mutex> lock(mutex_);
            if (pending_.empty()) return;
        }
    }
}

}  // namespace aar
