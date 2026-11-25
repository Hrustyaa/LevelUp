package com.levelup.levelup_test

/** The Android side of the one-use request created when a user starts at the Gate. */
internal class GateAuthorization {
    private var claimedTarget: String? = null

    fun claim(requestedTarget: String?, currentTarget: String, eligible: Boolean): Boolean {
        if (requestedTarget != null) {
            claimedTarget = requestedTarget.takeIf { eligible && it == currentTarget }
            return claimedTarget != null
        }
        return false
    }

    fun takeGrant(
        expectedTarget: String?,
        currentTarget: String,
        eligible: Boolean,
        minutes: Int?,
        nowMs: Long,
        unlockUntilMs: Long,
    ): Long? {
        if (!eligible || expectedTarget == null || expectedTarget != currentTarget ||
            expectedTarget != claimedTarget || minutes != 5 || unlockUntilMs > nowMs
        ) return null

        clear()
        return nowMs + 300_000L
    }

    fun clear() {
        claimedTarget = null
    }
}
