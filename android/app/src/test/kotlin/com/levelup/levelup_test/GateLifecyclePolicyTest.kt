package com.levelup.levelup_test

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GateLifecyclePolicyTest {
    private val instagram = "com.instagram.android"
    private val levelUp = "com.levelup.levelup_test"
    private val chrome = "com.android.chrome"
    private val settings = "com.android.settings"
    private val launcher = "com.google.android.apps.nexuslauncher"
    private val systemUi = "com.android.systemui"

    private fun baseState(
        focusEnabled: Boolean = true,
        isKeyguardLocked: Boolean = false,
        selectedTarget: String = instagram,
        unlockUntilMs: Long = 0L,
        nowMs: Long = 10_000L,
        uptimeMs: Long = 5_000L,
        foregroundPackage: String? = instagram,
        isForegroundCandidateApp: Boolean = true,
        gatedPackage: String? = null,
        ignoreReentryUntilUptimeMs: Long = 0L,
    ) = GateStateSnapshot(
        focusEnabled = focusEnabled,
        isKeyguardLocked = isKeyguardLocked,
        selectedTarget = selectedTarget,
        unlockUntilMs = unlockUntilMs,
        nowMs = nowMs,
        uptimeMs = uptimeMs,
        foregroundPackage = foregroundPackage,
        isForegroundCandidateApp = isForegroundCandidateApp,
        gatedPackage = gatedPackage,
        ignoreReentryUntilUptimeMs = ignoreReentryUntilUptimeMs,
    )

    @Test
    fun `shows gate when focus enabled, locked target is foreground, and no unlock active`() {
        val action = GateLifecyclePolicy.evaluate(baseState())
        assertEquals(GateAction.ShowGate(instagram), action)
    }

    @Test
    fun `does not show duplicate gate on rapid repeated events while latched`() {
        repeat(10) {
            val action = GateLifecyclePolicy.evaluate(
                baseState(gatedPackage = instagram, foregroundPackage = instagram)
            )
            assertEquals(GateAction.None, action)
        }
    }

    @Test
    fun `dismisses gate immediately when user swipes Home to launcher`() {
        val action = GateLifecyclePolicy.evaluate(
            baseState(
                gatedPackage = instagram,
                foregroundPackage = launcher,
                isForegroundCandidateApp = true,
            )
        )
        assertEquals(GateAction.DismissGate("foreground changed to $launcher"), action)
    }

    @Test
    fun `dismiss idempotency after gate already cleared on launcher`() {
        val afterDismiss = GateLifecyclePolicy.evaluate(
            baseState(
                gatedPackage = null,
                foregroundPackage = launcher,
                isForegroundCandidateApp = true,
            )
        )
        assertEquals(GateAction.None, afterDismiss)
    }

    @Test
    fun `does not dismiss gate on unrelated system ui windows`() {
        val action = GateLifecyclePolicy.evaluate(
            baseState(
                gatedPackage = instagram,
                foregroundPackage = systemUi,
                isForegroundCandidateApp = false,
            )
        )
        assertEquals(GateAction.None, action)
    }

    @Test
    fun `does not dismiss gate when foreground package is transiently null`() {
        val action = GateLifecyclePolicy.evaluate(
            baseState(
                gatedPackage = instagram,
                foregroundPackage = null,
                isForegroundCandidateApp = false,
            )
        )
        assertEquals(GateAction.None, action)
    }

    @Test
    fun `dismisses gate when user switches to LevelUp`() {
        val action = GateLifecyclePolicy.evaluate(
            baseState(
                gatedPackage = instagram,
                foregroundPackage = levelUp,
                isForegroundCandidateApp = true,
            )
        )
        assertTrue(action is GateAction.DismissGate)
    }

    @Test
    fun `dismisses gate when user switches to unrestricted apps like Chrome or Settings`() {
        for (pkg in listOf(chrome, settings)) {
            val action = GateLifecyclePolicy.evaluate(
                baseState(
                    gatedPackage = instagram,
                    foregroundPackage = pkg,
                    isForegroundCandidateApp = true,
                )
            )
            assertEquals(GateAction.DismissGate("foreground changed to $pkg"), action)
        }
    }

    @Test
    fun `reappears when returning to blocked target after leaving for Home or another app`() {
        val action = GateLifecyclePolicy.evaluate(
            baseState(
                gatedPackage = null,
                foregroundPackage = instagram,
                unlockUntilMs = 0L,
            )
        )
        assertEquals(GateAction.ShowGate(instagram), action)
    }

    @Test
    fun `dismisses gate when focus is disabled`() {
        val action = GateLifecyclePolicy.evaluate(
            baseState(focusEnabled = false, gatedPackage = instagram)
        )
        assertEquals(GateAction.DismissGate("disabled"), action)
    }

    @Test
    fun `dismisses gate when keyguard is locked`() {
        val action = GateLifecyclePolicy.evaluate(
            baseState(isKeyguardLocked = true, gatedPackage = instagram)
        )
        assertEquals(GateAction.DismissGate("keyguard"), action)
    }

    @Test
    fun `dismisses gate on unlock, stays hidden during 300s window, and reappears on expiry`() {
        val granted = GateLifecyclePolicy.evaluate(
            baseState(
                gatedPackage = instagram,
                unlockUntilMs = 310_000L,
                nowMs = 10_000L,
            )
        )
        assertEquals(GateAction.DismissGate("access granted"), granted)

        val duringUnlock = GateLifecyclePolicy.evaluate(
            baseState(
                gatedPackage = null,
                foregroundPackage = instagram,
                unlockUntilMs = 310_000L,
                nowMs = 309_999L,
            )
        )
        assertEquals(GateAction.None, duringUnlock)

        val expired = GateLifecyclePolicy.evaluate(
            baseState(
                gatedPackage = null,
                foregroundPackage = instagram,
                unlockUntilMs = 310_000L,
                nowMs = 310_000L,
            )
        )
        assertEquals(GateAction.ShowGate(instagram), expired)
    }

    @Test
    fun `rapid app switching sequence produces clean show and dismiss transitions`() {
        // 1. Open Instagram -> ShowGate
        assertEquals(
            GateAction.ShowGate(instagram),
            GateLifecyclePolicy.evaluate(baseState(gatedPackage = null, foregroundPackage = instagram)),
        )
        // 2. Swipe Home -> DismissGate
        assertEquals(
            GateAction.DismissGate("foreground changed to $launcher"),
            GateLifecyclePolicy.evaluate(baseState(gatedPackage = instagram, foregroundPackage = launcher)),
        )
        // 3. Open Chrome -> None (already dismissed)
        assertEquals(
            GateAction.None,
            GateLifecyclePolicy.evaluate(baseState(gatedPackage = null, foregroundPackage = chrome)),
        )
        // 4. Switch back to Instagram -> ShowGate
        assertEquals(
            GateAction.ShowGate(instagram),
            GateLifecyclePolicy.evaluate(baseState(gatedPackage = null, foregroundPackage = instagram)),
        )
    }

    @Test
    fun `respects navigation grace period after tapping Start Challenge or Go Back`() {
        val duringGrace = GateLifecyclePolicy.evaluate(
            baseState(
                gatedPackage = null,
                foregroundPackage = instagram,
                uptimeMs = 6_000L,
                ignoreReentryUntilUptimeMs = 6_800L,
            )
        )
        assertEquals(GateAction.None, duringGrace)
    }
}
