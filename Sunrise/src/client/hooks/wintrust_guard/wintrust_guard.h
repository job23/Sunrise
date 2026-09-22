#pragma once

namespace sunrise::client::hooks::wintrust_guard {

/**
 * Makes two wintrust helpers null-safe under Wine.
 * The Client calls WTHelperGetProvCertFromChain with the signer WTHelperGetProvSignerFromChain
 * returned, which is null when no signature chain was built. Windows answers null; Wine builds
 * before merge request 11545 (August 2026, after CrossOver 26.3) dereference it and crash.
 * Safe before Core logging exists; the outcome waits for report_installation().
 * @return True when both detours attached, or when the host is Windows and none are needed.
 */
[[nodiscard]] bool install() noexcept;

/**
 * Writes the one install line. install() may run before the log sinks exist, so the outcome is
 * kept and reported from here once they do. Reports at most once.
 */
void report_installation() noexcept;

/** @return True when the detours are detached, or were never attached. */
[[nodiscard]] bool uninstall() noexcept;

} // namespace sunrise::client::hooks::wintrust_guard
