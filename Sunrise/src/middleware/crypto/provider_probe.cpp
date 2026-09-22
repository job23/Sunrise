#include "provider_probe.h"

#include <Windows.h>

#include <bcrypt.h>
#include <cstddef>

#include "../../core/logging/log.h"

namespace sunrise::middleware::crypto::provider_probe {
namespace {

/** One chaining mode as CNG takes it: the whole null-terminated wide string and its byte size. */
struct ChainingMode {
    const wchar_t* name{};
    ULONG size{};
};

/** @return The chaining-mode property for one of the SDK's constant mode strings. */
template <std::size_t Length>
[[nodiscard]] constexpr ChainingMode chaining_mode(const wchar_t (&name)[Length]) noexcept {
    return ChainingMode{name, static_cast<ULONG>(sizeof(wchar_t) * Length)};
}

/** No chaining mode, for a hash algorithm. */
constexpr ChainingMode kNoChainingMode{};

/**
 * Opens one algorithm, optionally sets its chaining mode, and closes it.
 * Only CNG is called here: this runs before the hooks, on a host that may be Wine, so the probe
 * stays clear of every other system export.
 * @param algorithmId CNG algorithm identifier.
 * @param mode Chaining mode to set, or kNoChainingMode for a hash.
 * @param flags Provider open flags, such as the HMAC flag.
 * @return True when every step succeeded.
 */
[[nodiscard]] bool
open_once(const wchar_t* algorithmId, const ChainingMode& mode, ULONG flags) noexcept {
    BCRYPT_ALG_HANDLE algorithm = nullptr;
    if (BCryptOpenAlgorithmProvider(&algorithm, algorithmId, nullptr, flags) < 0
        || algorithm == nullptr) {
        return false;
    }
    bool available = true;
    if (mode.name != nullptr) {
        available = BCryptSetProperty(algorithm,
                                      BCRYPT_CHAINING_MODE,
                                      reinterpret_cast<PUCHAR>(const_cast<wchar_t*>(mode.name)),
                                      mode.size,
                                      0)
                    >= 0;
    }
    BCryptCloseAlgorithmProvider(algorithm, 0);
    return available;
}

/** Writes one warning naming a primitive the host cannot provide. */
void warn_missing(const char* name) noexcept {
    core::log::writef(core::log::Channel::middleware,
                      core::log::Level::warn,
                      "ev=crypto_probe primitive=%s result=missing",
                      name);
}

} // namespace

/** Opens each CNG provider the sign-on and gameplay paths depend on. */
Report probe() noexcept {
    Report report{};
    report.aesCbc = open_once(BCRYPT_AES_ALGORITHM, chaining_mode(BCRYPT_CHAIN_MODE_CBC), 0);
    report.aesGcm = open_once(BCRYPT_AES_ALGORITHM, chaining_mode(BCRYPT_CHAIN_MODE_GCM), 0);
    report.sha256 = open_once(BCRYPT_SHA256_ALGORITHM, kNoChainingMode, 0);
    report.sha1 = open_once(BCRYPT_SHA1_ALGORITHM, kNoChainingMode, 0);
    report.hmacSha256 =
        open_once(BCRYPT_SHA256_ALGORITHM, kNoChainingMode, BCRYPT_ALG_HANDLE_HMAC_FLAG);
    return report;
}

/** @return True when every probed primitive is available. */
bool complete(const Report& report) noexcept {
    return report.aesCbc && report.aesGcm && report.sha256 && report.sha1 && report.hmacSha256;
}

/** Writes one line per missing primitive, or one info line when all are present. */
void log_report(const Report& report) noexcept {
    if (complete(report)) {
        core::log::write(core::log::Channel::middleware,
                         core::log::Level::info,
                         "ev=crypto_probe result=complete");
        return;
    }
    if (!report.aesCbc) {
        warn_missing("aes_cbc");
    }
    if (!report.aesGcm) {
        warn_missing("aes_gcm");
    }
    if (!report.sha256) {
        warn_missing("sha256");
    }
    if (!report.sha1) {
        warn_missing("sha1");
    }
    if (!report.hmacSha256) {
        warn_missing("hmac_sha256");
    }
}

} // namespace sunrise::middleware::crypto::provider_probe
