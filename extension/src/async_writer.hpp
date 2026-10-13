#pragma once
// Appends text to a file from a background thread so disk IO never stalls
// the game thread.

#include <condition_variable>
#include <fstream>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace aar {

class async_writer {
public:
    async_writer() = default;
    ~async_writer() { close(); }
    async_writer(const async_writer&) = delete;
    async_writer& operator=(const async_writer&) = delete;

    bool open(const std::string& path);
    void write(std::string text);
    void close();
    bool is_open() const { return running_; }

private:
    void run();

    std::ofstream file_;
    std::thread thread_;
    std::mutex mutex_;
    std::condition_variable cv_;
    std::vector<std::string> pending_;
    bool stop_ = false;
    bool running_ = false;
};

}  // namespace aar
