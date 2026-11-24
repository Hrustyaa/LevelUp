package com.levelup.levelup_test

/**
 * Pure Kotlin decision policy for [LevelUpAccessibilityService] gate lifecycle.
 *
 * Kept free of Android framework dependencies so every transition (eligibility,
 * app switching, leaving for Home, rapid events, unlock expiry, focus disable,
 * no-duplicate-overlay) can be verified directly with JVM unit tests.
 */
data class GateStateSnapshot(
    val focusEnabled: Boolean,
    val isKeyguardLocked: Boolean,
    val selectedTarget: String,
    val unlockUntilMs: Long,
    val nowMs: Long,
    val uptimeMs: Long,
    val foregroundPackage: String?,
    val isForegroundCandidateApp: Boolean,
    val gatedPackage: String?,
    val ignoreReentryUntilUptimeMs: Long,
)

sealed class GateAction {
    data object None : GateAction()
    data class ShowGate(val targetPackage: String) : GateAction()
    data class DismissGate(val reason: String) : GateAction()
}

object GateLifecyclePolicy {
    fun evaluate(state: GateStateSnapshot): GateAction {
        if (!state.focusEnabled) {
            return if (state.gatedPackage != null) {
                GateAction.DismissGate("disabled")
            } else {
                GateAction.None
            }
        }

        if (state.isKeyguardLocked) {
            return if (state.gatedPackage != null) {
                GateAction.DismissGate("keyguard")
            } else {
                GateAction.None
            }
        }

        val unlocked = state.unlockUntilMs > state.nowMs

        if (state.gatedPackage != null) {
            if (unlocked) {
                return GateAction.DismissGate("access granted")
            }
            if (state.gatedPackage != state.selectedTarget) {
                return GateAction.DismissGate("target changed")
            }

            // Dismiss whenever the foreground TYPE_APPLICATION window changes to
            // another candidate app (including Home Launcher, LevelUp, or any
            // unrestricted app). System UI / transient windows (notifications,
            // volume, permission dialogs) have isForegroundCandidateApp == false
            // and never dismiss the latched gate.
            val fg = state.foregroundPackage
            if (fg != null &&
                fg != state.gatedPackage &&
                state.isForegroundCandidateApp
            ) {
                return GateAction.DismissGate("foreground changed to $fg")
            }
            return GateAction.None
        }

        if (state.uptimeMs < state.ignoreReentryUntilUptimeMs) {
            return GateAction.None
        }
        if (unlocked) {
            return GateAction.None
        }
        if (state.foregroundPackage == state.selectedTarget) {
            return GateAction.ShowGate(state.selectedTarget)
        }
        return GateAction.None
    }
}
