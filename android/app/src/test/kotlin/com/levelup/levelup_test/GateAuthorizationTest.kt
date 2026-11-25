package com.levelup.levelup_test

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GateAuthorizationTest {
    @Test
    fun grantConsumesAnEligibleClaimAndUsesTheFixedDuration() {
        val authorization = GateAuthorization()
        assertNull(authorization.takeGrant("selected", "selected", true, 5, 1000, 0))
        assertTrue(authorization.claim("selected", "selected", true))
        assertFalse(authorization.claim(null, "selected", true))
        assertEquals(301_000L, authorization.takeGrant("selected", "selected", true, 5, 1000, 0))
        assertNull(authorization.takeGrant("selected", "selected", true, 5, 302_000, 0))
    }

    @Test
    fun grantRequiresMatchingTargetEligibilityAndDuration() {
        val authorization = GateAuthorization()
        assertFalse(authorization.claim("former", "selected", true))
        assertFalse(authorization.claim("selected", "selected", false))
        assertTrue(authorization.claim("selected", "selected", true))
        assertNull(authorization.takeGrant(null, "selected", true, 5, 1000, 0))
        assertNull(authorization.takeGrant("selected", "different", true, 5, 1000, 0))
        assertNull(authorization.takeGrant("selected", "selected", false, 5, 1000, 0))
        assertNull(authorization.takeGrant("selected", "selected", true, 4, 1000, 0))
        assertNull(authorization.takeGrant("selected", "selected", true, 5, 1000, 2000))
        authorization.clear()
        assertNull(authorization.takeGrant("selected", "selected", true, 5, 1000, 0))
    }
}
