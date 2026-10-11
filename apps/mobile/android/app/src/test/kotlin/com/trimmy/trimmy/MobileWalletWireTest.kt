package com.trimmy.trimmy

import org.junit.Assert.*
import org.junit.Test

class MobileWalletWireTest {
    private val payer = ByteArray(32) { 7 }
    private val destination = ByteArray(32) { 8 }
    private val source = MobileWalletWire.encode(payer)

    private fun transfer(versioned: Boolean = true): ByteArray {
        // One unsigned SOL transfer: payer, recipient, system program.
        val prefix = byteArrayOf(1) + ByteArray(64)
        val header = (if (versioned) byteArrayOf(0x80.toByte()) else byteArrayOf()) + byteArrayOf(1, 0, 1, 3)
        val accounts = payer + destination + ByteArray(32)
        val blockhash = ByteArray(32) { 9 }
        val instruction = byteArrayOf(1, 2, 2, 0, 1, 12, 2, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0)
        return prefix + header + accounts + blockhash + instruction + (if (versioned) byteArrayOf(0) else byteArrayOf())
    }

    private fun invalid(wire: ByteArray, expected: String = source) {
        try {
            MobileWalletWire.validate(wire, expected)
            fail("Invalid transaction passed")
        } catch (error: MobileWalletFailure) {
            assertEquals("MOBILE_WALLET_INVALID_TRANSACTION", error.code)
        }
    }

    @Test fun acceptsVersionZeroAndLegacySingleSignerTransfers() {
        assertTrue(MobileWalletWire.validate(transfer(), source))
        assertFalse(MobileWalletWire.validate(transfer(false), source))
    }

    @Test fun rejectsDifferentPayerAndExistingSignature() {
        invalid(transfer(), MobileWalletWire.encode(destination))
        invalid(transfer().apply { this[1] = 1 })
    }

    @Test fun rejectsExtraSignerUnknownVersionAndLookupTable() {
        invalid(transfer().apply { this[0] = 2 })
        invalid(transfer().apply { this[65] = 0x81.toByte() })
        invalid(transfer().apply { this[lastIndex] = 1 })
    }

    @Test fun rejectsTruncationAndAppendedData() {
        invalid(transfer().dropLast(1).toByteArray())
        invalid(transfer() + byteArrayOf(0))
        invalid(byteArrayOf())
    }

    @Test fun rejectsInvalidInstructionAccountIndex() {
        val wire = transfer()
        val instructionProgramIndex = 65 + 1 + 4 + 96 + 32 + 1
        wire[instructionProgramIndex] = 9
        invalid(wire)
    }

    @Test fun base58PreservesLeadingZerosAndExactKeyLength() {
        assertEquals("1".repeat(32), MobileWalletWire.encode(ByteArray(32)))
        assertArrayEquals(ByteArray(32), MobileWalletWire.decode("1".repeat(32)))
        assertArrayEquals(payer, MobileWalletWire.decode(source))
        assertTrue(MobileWalletWire.isSignature("1".repeat(64)))
        assertFalse(MobileWalletWire.isSignature("1".repeat(32)))
    }

    @Test fun requestHashUsesTheExactUnsignedWire() {
        val first = MobileWalletWire.hash(transfer())
        assertEquals(64, first.length)
        assertNotEquals(first, MobileWalletWire.hash(transfer().apply { this[170] = 12 }))
    }

    @Test fun nativeResolutionIsIdempotentAfterDartJournalClearWasInterrupted() {
        val hash = MobileWalletWire.hash(transfer())
        val signature = "1".repeat(64)
        assertTrue(MobileWalletRecovery.wasResolved(hash, signature, setOf(hash), true))
        assertFalse(MobileWalletRecovery.wasResolved(hash, signature, emptySet(), true))
        assertFalse(MobileWalletRecovery.wasResolved(hash, "invalid", setOf(hash), true))
        assertTrue(MobileWalletRecovery.wasResolved(hash, null, setOf(hash), false))
    }

    @Test fun postDispatchTimeoutCancellationAndSessionLossStayUncertain() {
        assertEquals("OUTCOME_UNKNOWN", MobileWalletOutcome.failure(true, false, timedOut = true))
        assertEquals("OUTCOME_UNKNOWN", MobileWalletOutcome.failure(true, false, cancelled = true))
        assertEquals("OUTCOME_UNKNOWN", MobileWalletOutcome.failure(true, false, "MOBILE_WALLET_SESSION_LOST"))
        assertEquals("OUTCOME_UNKNOWN", MobileWalletOutcome.failure(true, false))
    }

    @Test fun onlyDefiniteWalletRefusalIsSafeAfterDispatch() {
        assertEquals("CANCELLED", MobileWalletOutcome.failure(true, true))
        assertEquals("TIMEOUT", MobileWalletOutcome.failure(false, false, timedOut = true))
        assertEquals("CANCELLED", MobileWalletOutcome.failure(false, false, cancelled = true))
        assertEquals("ACCOUNT_CHANGED", MobileWalletOutcome.failure(false, false, "MOBILE_WALLET_ACCOUNT_CHANGED"))
    }
}
