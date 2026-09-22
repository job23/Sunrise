#pragma once

namespace sunrise::middleware::crypto::provider_probe {

/** Which CNG primitives the host provides. Wine builds differ, so nothing here is assumed. */
struct Report {
    bool aesCbc{};
    bool aesGcm{};
    bool sha256{};
    bool sha1{};
    bool hmacSha256{};
};

/**
 * Opens each CNG provider the sign-on and gameplay paths depend on, then closes it again.
 * @return One flag per primitive, true when the host can open it with the mode used here.
 */
[[nodiscard]] Report probe() noexcept;

/** @return True when every probed primitive is available. */
[[nodiscard]] bool complete(const Report& report) noexcept;

/**
 * Writes one middleware line naming each missing primitive, and one info line when all are
 * present. A missing primitive would otherwise surface later as an opaque sign-on failure.
 * @param report The result of probe().
 */
void log_report(const Report& report) noexcept;

} // namespace sunrise::middleware::crypto::provider_probe
