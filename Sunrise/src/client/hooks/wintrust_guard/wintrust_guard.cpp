#include "wintrust_guard.h"

#include <Windows.h>

#include <array>
#include <cstddef>
#include <mutex>
#include <span>
#include <wintrust.h>

#include "../../../core/logging/log.h"
#include "../../../core/runtime/host_environment.h"
#include "../../../core/threading/srw_lock.h"
#include "../../hooking/detour.h"

namespace sunrise::client::hooks::wintrust_guard {
namespace {

using CertFromChain = CRYPT_PROVIDER_CERT*(WINAPI*)(CRYPT_PROVIDER_SGNR*, DWORD);
using SignerFromChain = CRYPT_PROVIDER_SGNR*(WINAPI*)(CRYPT_PROVIDER_DATA*, DWORD, BOOL, DWORD);

constexpr wchar_t kModuleName[] = L"wintrust.dll";
constexpr std::size_t kHookCount = 2;

core::threading::SrwLock g_lock{};
HMODULE g_module{};
std::array<hooking::detour::Handle, kHookCount> g_handles{};
bool g_installed{};
/** Outcome text of the install attempt, kept until the log can carry it. */
const char* g_outcome{};
bool g_reported{};

/** @return Null for a null signer, which is what Windows answers; the original otherwise. */
CRYPT_PROVIDER_CERT* WINAPI cert_from_chain(CRYPT_PROVIDER_SGNR* signer, DWORD index) noexcept {
    const auto original = reinterpret_cast<CertFromChain>(g_handles[0].original);
    if (signer == nullptr || original == nullptr) {
        return nullptr;
    }
    return original(signer, index);
}

/** @return Null for null provider data, which is what Windows answers; the original otherwise. */
CRYPT_PROVIDER_SGNR* WINAPI signer_from_chain(CRYPT_PROVIDER_DATA* data,
                                              DWORD index,
                                              BOOL counterSigner,
                                              DWORD counterIndex) noexcept {
    const auto original = reinterpret_cast<SignerFromChain>(g_handles[1].original);
    if (data == nullptr || original == nullptr) {
        return nullptr;
    }
    return original(data, index, counterSigner, counterIndex);
}

/** @param result Outcome text kept for report_installation(). */
void report(const char* result) noexcept {
    g_outcome = result;
}

} // namespace

/** Attaches both helper detours when the host is Wine. */
bool install() noexcept {
    if (!core::runtime::is_wine()) {
        return true;
    }
    const std::lock_guard lock(g_lock);
    if (g_installed) {
        return true;
    }
    // Pinned for the detour's lifetime. The Client loads the module itself later, so this only
    // brings the load forward.
    g_module = LoadLibraryExW(kModuleName, nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (g_module == nullptr) {
        report("no_module");
        return false;
    }
    const std::array<hooking::detour::Spec, kHookCount> specs{
        hooking::detour::Spec{
            reinterpret_cast<void*>(GetProcAddress(g_module, "WTHelperGetProvCertFromChain")),
            reinterpret_cast<void*>(&cert_from_chain)},
        hooking::detour::Spec{
            reinterpret_cast<void*>(GetProcAddress(g_module, "WTHelperGetProvSignerFromChain")),
            reinterpret_cast<void*>(&signer_from_chain)},
    };
    for (const hooking::detour::Spec& spec : specs) {
        if (spec.target == nullptr) {
            report("no_export");
            FreeLibrary(g_module);
            g_module = nullptr;
            return false;
        }
    }
    if (!hooking::detour::install(std::span<const hooking::detour::Spec>(specs),
                                  std::span<hooking::detour::Handle>(g_handles))) {
        report("attach_fail");
        FreeLibrary(g_module);
        g_module = nullptr;
        return false;
    }
    g_installed = true;
    report("ok");
    return true;
}

/** Writes the one install line once logging exists. */
void report_installation() noexcept {
    const std::lock_guard lock(g_lock);
    if (g_reported || g_outcome == nullptr) {
        return;
    }
    g_reported = true;
    const bool ok = g_installed;
    core::log::writef(core::log::Channel::client,
                      ok ? core::log::Level::info : core::log::Level::warn,
                      "ev=hook stage=install group=wintrust_guard count=%u result=%s",
                      ok ? 2U : 0U,
                      g_outcome);
}

/** Detaches both detours and releases the module pin. */
bool uninstall() noexcept {
    const std::lock_guard lock(g_lock);
    if (!g_installed) {
        return true;
    }
    if (!hooking::detour::uninstall(std::span<hooking::detour::Handle>(g_handles))) {
        return false;
    }
    g_installed = false;
    if (g_module != nullptr) {
        FreeLibrary(g_module);
        g_module = nullptr;
    }
    return true;
}

} // namespace sunrise::client::hooks::wintrust_guard
