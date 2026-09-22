#include "host_environment.h"

#include <Windows.h>

#include "../logging/log.h"

namespace sunrise::core::runtime {
namespace {

/** Wine's ntdll export that names the host kernel. Windows never has it. */
using WineGetHostVersion = void(__cdecl*)(const char** system, const char** release);

/** @return The Wine host report, resolved once because the host cannot change. */
const WineHostVersion& resolved_host_version() noexcept {
    static const WineHostVersion version = [] {
        WineHostVersion output{};
        const HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
        if (ntdll == nullptr) {
            return output;
        }
        const auto getHostVersion =
            reinterpret_cast<WineGetHostVersion>(GetProcAddress(ntdll, "wine_get_host_version"));
        if (getHostVersion == nullptr) {
            return output;
        }
        const char* system = nullptr;
        const char* release = nullptr;
        getHostVersion(&system, &release);
        if (system != nullptr) {
            output.system = system;
        }
        if (release != nullptr) {
            output.release = release;
        }
        return output;
    }();
    return version;
}

} // namespace

/** @return True when the loaded ntdll exports Wine's own version entry point. */
bool is_wine() noexcept {
    // Wine exports this from ntdll to name itself and Windows never does. The host cannot change
    // while the process lives, so the answer is resolved once.
    static const bool underWine = [] {
        const HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
        return ntdll != nullptr && GetProcAddress(ntdll, "wine_get_version") != nullptr;
    }();
    return underWine;
}

/** @return Borrowed Wine-owned strings, or empty views when not under Wine. */
WineHostVersion wine_host_version() noexcept {
    return is_wine() ? resolved_host_version() : WineHostVersion{};
}

/** Writes one core info line naming the host. */
void log_host() noexcept {
    if (!is_wine()) {
        log::write(log::Channel::core, log::Level::info, "ev=host wine=0 system=Windows");
        return;
    }
    const WineHostVersion version = wine_host_version();
    log::writef(log::Channel::core,
                log::Level::info,
                "ev=host wine=1 system=%.*s release=%.*s",
                static_cast<int>(version.system.size()),
                version.system.data(),
                static_cast<int>(version.release.size()),
                version.release.data());
}

} // namespace sunrise::core::runtime
