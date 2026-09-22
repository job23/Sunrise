#pragma once

#include <string_view>

namespace sunrise::core::runtime {

/** Wine's own report of the kernel it runs on. Both views are empty on Windows. */
struct WineHostVersion {
    std::string_view system;
    std::string_view release;
};

/**
 * Reports whether the process runs under Wine instead of Windows.
 * @return True when the loaded ntdll exports Wine's own version entry point.
 */
[[nodiscard]] bool is_wine() noexcept;

/**
 * Reads Wine's host kernel name and release, which CrossOver and GPTK also export.
 * @return Borrowed Wine-owned strings, or empty views when not under Wine.
 */
[[nodiscard]] WineHostVersion wine_host_version() noexcept;

/** Writes one core info line naming the host, so bug reports show Windows, Linux or macOS. */
void log_host() noexcept;

} // namespace sunrise::core::runtime
