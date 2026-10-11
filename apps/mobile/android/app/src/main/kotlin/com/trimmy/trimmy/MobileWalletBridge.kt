package com.trimmy.trimmy

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.util.Base64
import com.solana.mobilewalletadapter.clientlib.ConnectionIdentity
import com.solana.mobilewalletadapter.clientlib.MobileWalletAdapter
import com.solana.mobilewalletadapter.clientlib.Solana
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.math.BigInteger
import java.security.MessageDigest
import java.util.UUID

internal class MobileWalletFailure(val code: String) : Exception(code)

/** No Privy state, authentication token, signing key or transaction is persisted here. */
internal object MobileWalletBridge {
    const val CHANNEL = "com.trimmy.trimmy/mobile_wallet"
    private const val PREFS = "trimmy.mobile_wallet_funding.v1"
    private var prefs: SharedPreferences? = null
    @Volatile private var current: Request? = null
    var adapter: MobileWalletAdapter? = null
        private set
    var connectedAddress: String? = null
        private set

    class Request(
        val id: String,
        val method: String,
        val result: MethodChannel.Result,
        val address: String? = null,
        val wire: ByteArray? = null,
        val requestHash: String? = null,
    ) {
        @Volatile var dispatched = false
        var started = false
    }

    fun handle(activity: Activity, call: MethodCall, result: MethodChannel.Result) {
        if (prefs == null) prefs = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        try {
            if (call.method == "getPendingOperation") {
                result.success(pending())
                return
            }
            if (current != null) fail("BUSY")
            when (call.method) {
                "acknowledgeUnknownOutcome", "resolvePending" -> {
                    val hash = call.argument<String>("requestHash")
                    if (hash == null || !Regex("[a-f0-9]{64}").matches(hash)) fail("INVALID_REQUEST")
                    val marker = pending()
                    if (marker == null) {
                        val signature = call.argument<String>("signature")
                        val resolved = MobileWalletRecovery.wasResolved(
                            hash,
                            if (call.method == "resolvePending") signature else null,
                            prefs!!.getStringSet("used", emptySet())!!,
                            requireSignature = call.method == "resolvePending",
                        )
                        if (!resolved) fail("INVALID_REQUEST")
                        // Native clear may commit just before the Dart journal
                        // clear is interrupted. Reconciliation is idempotent.
                        result.success(null)
                        return
                    }
                    if (hash != marker["requestHash"]) fail("INVALID_REQUEST")
                    if (call.method == "acknowledgeUnknownOutcome") {
                        if (marker["signature"] != null) fail("INVALID_REQUEST")
                    } else {
                        val signature = call.argument<String>("signature") ?: fail("INVALID_REQUEST")
                        if (!MobileWalletWire.isSignature(signature) ||
                            (marker["signature"] != null && marker["signature"] != signature)) {
                            fail("INVALID_REQUEST")
                        }
                    }
                    // Resolution is called only after exact API reconciliation;
                    // acknowledgement requires a separate, explicit user action.
                    clearPending(hash)
                    result.success(null)
                }
                "connect", "disconnect", "signAndSend" -> {
                    var address: String? = null
                    var wire: ByteArray? = null
                    var hash: String? = null
                    if (call.method == "signAndSend") {
                        if (pending() != null) fail("OUTCOME_UNKNOWN")
                        address = call.argument<String>("address") ?: fail("INVALID_TRANSACTION")
                        if (connectedAddress == null || adapter == null) fail("NOT_CONNECTED")
                        if (address != connectedAddress) fail("ACCOUNT_CHANGED")
                        val encoded = call.argument<String>("unsignedTransaction") ?: fail("INVALID_TRANSACTION")
                        if (encoded.length > 1644) fail("INVALID_TRANSACTION")
                        wire = try { Base64.decode(encoded, Base64.NO_WRAP) } catch (_: Exception) {
                            fail("INVALID_TRANSACTION")
                        }
                        MobileWalletWire.validate(wire, address)
                        hash = MobileWalletWire.hash(wire)
                        if (prefs!!.getStringSet("used", emptySet())!!.contains(hash)) fail("INVALID_TRANSACTION")
                    }
                    if (call.method == "disconnect" && adapter == null) {
                        connectedAddress = null
                        result.success(null)
                        return
                    }
                    val request = Request(UUID.randomUUID().toString(), call.method, result, address, wire, hash)
                    current = request
                    try {
                        activity.startActivity(Intent(activity, MobileWalletActivity::class.java).putExtra("request", request.id))
                    } catch (_: Exception) {
                        complete(request, error = "MOBILE_WALLET_UNAVAILABLE")
                    }
                }
                else -> result.notImplemented()
            }
        } catch (error: MobileWalletFailure) {
            result.error(error.code, error.code, null)
        } catch (_: Exception) {
            result.error("MOBILE_WALLET_UNAVAILABLE", "MOBILE_WALLET_UNAVAILABLE", null)
        }
    }

    fun request(id: String?): Request? = current?.takeIf { it.id == id }
    fun isCurrent(request: Request): Boolean = current === request

    fun connection(): MobileWalletAdapter = adapter ?: MobileWalletAdapter(
        connectionIdentity = ConnectionIdentity(
            identityUri = Uri.parse("https://trimmy.xyz"),
            iconUri = Uri.parse("favicon.png"),
            identityName = "Trimmy",
        ),
    ).also {
        it.blockchain = Solana.Mainnet
        adapter = it
    }

    fun connected(address: String) { connectedAddress = address }
    fun forgetConnection() {
        adapter = null
        connectedAddress = null
    }

    @Synchronized fun markDispatched(request: Request) {
        if (!isCurrent(request) || pending() != null) fail("OUTCOME_UNKNOWN")
        val saved = prefs!!.edit()
            .putString("pending_address", request.address)
            .putString("pending_hash", request.requestHash)
            .remove("pending_signature")
            .commit()
        if (!saved) fail("STORAGE")
        // Persist first: death after this line must never silently enable retry.
        request.dispatched = true
    }

    fun saveSignature(request: Request, signature: String) {
        if (!isCurrent(request) || pending()?.get("requestHash") != request.requestHash ||
            !prefs!!.edit().putString("pending_signature", signature).commit()) {
            fail("OUTCOME_UNKNOWN")
        }
    }

    fun rejected(request: Request) {
        if (!isCurrent(request) || pending()?.get("requestHash") != request.requestHash) {
            fail("OUTCOME_UNKNOWN")
        }
        if (request.dispatched) clearPending(request.requestHash!!)
    }

    private fun clearPending(hash: String) {
        val used = prefs!!.getStringSet("used", emptySet())!!.toMutableSet().apply { add(hash) }
        if (!prefs!!.edit().putStringSet("used", used).remove("pending_address")
                .remove("pending_hash").remove("pending_signature").commit()) fail("STORAGE")
    }

    private fun pending(): Map<String, String>? {
        val store = prefs ?: return null
        val hash = store.getString("pending_hash", null) ?: return null
        val address = store.getString("pending_address", null) ?: fail("OUTCOME_UNKNOWN")
        return mutableMapOf("address" to address, "requestHash" to hash).apply {
            store.getString("pending_signature", null)?.let { put("signature", it) }
        }
    }

    fun complete(request: Request, value: Any? = null, error: String? = null) {
        if (!isCurrent(request)) return
        if (error != null) forgetConnection()
        current = null
        if (error == null) request.result.success(value) else request.result.error(error, error, null)
    }

    private fun fail(suffix: String): Nothing = throw MobileWalletFailure("MOBILE_WALLET_$suffix")
}

internal object MobileWalletRecovery {
    fun wasResolved(hash: String, signature: String?, used: Set<String>, requireSignature: Boolean): Boolean =
        Regex("[a-f0-9]{64}").matches(hash) && used.contains(hash) &&
            (!requireSignature || signature != null && MobileWalletWire.isSignature(signature))
}

/** The send boundary is irreversible: only a definite wallet refusal is safe to retry. */
internal object MobileWalletOutcome {
    fun failure(
        dispatched: Boolean,
        refused: Boolean,
        localCode: String? = null,
        timedOut: Boolean = false,
        cancelled: Boolean = false,
    ): String = when {
        dispatched -> if (refused) "CANCELLED" else "OUTCOME_UNKNOWN"
        localCode != null -> localCode.removePrefix("MOBILE_WALLET_")
        refused -> "CANCELLED"
        timedOut -> "TIMEOUT"
        cancelled -> "CANCELLED"
        else -> "UNAVAILABLE"
    }
}

/** Only one unsigned signer, the connected source. No message/key signing API. */
internal object MobileWalletWire {
    private const val ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    private val base = BigInteger.valueOf(58)

    fun encode(bytes: ByteArray): String {
        var n = BigInteger(1, bytes)
        val out = StringBuilder()
        while (n.signum() > 0) {
            val division = n.divideAndRemainder(base)
            out.append(ALPHABET[division[1].toInt()])
            n = division[0]
        }
        bytes.takeWhile { it == 0.toByte() }.forEach { _ -> out.append('1') }
        return out.reverse().toString()
    }

    fun decode(value: String): ByteArray {
        if (value.isEmpty() || value.length > 88) invalid()
        var n = BigInteger.ZERO
        for (char in value) {
            val digit = ALPHABET.indexOf(char)
            if (digit < 0) invalid()
            n = n.multiply(base).add(BigInteger.valueOf(digit.toLong()))
        }
        val bytes = if (n == BigInteger.ZERO) byteArrayOf() else n.toByteArray().dropWhile { it == 0.toByte() }.toByteArray()
        return ByteArray(value.takeWhile { it == '1' }.length) + bytes
    }

    fun isSignature(value: String): Boolean = try { decode(value).size == 64 } catch (_: Exception) { false }
    fun hash(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    fun validate(wire: ByteArray, source: String): Boolean {
        if (wire.size !in 134..1232 || wire[0] != 1.toByte() || wire.sliceArray(1..64).any { it != 0.toByte() }) invalid()
        val payer = decode(source)
        if (payer.size != 32) invalid()
        var index = 65
        val versioned = (wire[index].toInt() and 0x80) != 0
        if (versioned && (wire[index++].toInt() and 0xff) != 0x80) invalid()
        if (wire[index++].toInt() != 1 || wire[index++].toInt() != 0) invalid()
        val readonly = wire[index++].toInt() and 0xff
        val accounts = wire[index++].toInt() and 0xff
        // Funding transfers never need more than 32 static addresses or an ALT.
        if (accounts !in 1..32 || readonly >= accounts || index + accounts * 32 + 33 > wire.size) invalid()
        if (!wire.copyOfRange(index, index + 32).contentEquals(payer)) invalid()
        index += accounts * 32 + 32
        fun short(): Int {
            var out = 0
            var shift = 0
            while (true) {
                if (index >= wire.size || shift > 14) invalid()
                val byte = wire[index++].toInt() and 0xff
                out = out or ((byte and 127) shl shift)
                if ((byte and 128) == 0) return out
                shift += 7
            }
        }
        val instructions = short()
        if (instructions !in 1..8) invalid()
        repeat(instructions) {
            if (index >= wire.size || (wire[index++].toInt() and 0xff) >= accounts) invalid()
            val count = short()
            if (count > accounts || index + count > wire.size) invalid()
            repeat(count) { if ((wire[index++].toInt() and 0xff) >= accounts) invalid() }
            val size = short()
            if (index + size > wire.size) invalid()
            index += size
        }
        if (versioned && (index >= wire.size || wire[index++].toInt() != 0)) invalid()
        if (index != wire.size) invalid()
        return versioned
    }

    private fun invalid(): Nothing = throw MobileWalletFailure("MOBILE_WALLET_INVALID_TRANSACTION")
}
