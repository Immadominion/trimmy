package com.trimmy.trimmy

import android.os.Bundle
import android.view.Gravity
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.lifecycle.lifecycleScope
import com.solana.mobilewalletadapter.clientlib.ActivityResultSender
import com.solana.mobilewalletadapter.clientlib.TransactionParams
import com.solana.mobilewalletadapter.clientlib.TransactionResult
import com.solana.mobilewalletadapter.clientlib.protocol.JsonRpc20Client
import com.solana.mobilewalletadapter.common.ProtocolContract
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import java.util.concurrent.TimeoutException

/** Separate activity preserves FlutterActivity/Privy OAuth and notification handling. */
class MobileWalletActivity : ComponentActivity() {
    private val sender = ActivityResultSender(this)
    private var request: MobileWalletBridge.Request? = null
    private var completed = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val selected = MobileWalletBridge.request(intent.getStringExtra("request"))
        if (selected == null) {
            // Process death: the old callback/session is gone. Its durable
            // pending marker remains for reconciliation in the restored app.
            finish()
            return
        }
        request = selected
        if (savedInstanceState != null || selected.started) {
            finishFailure(if (selected.dispatched) "OUTCOME_UNKNOWN" else "SESSION_LOST")
            return
        }
        selected.started = true
        setContentView(TextView(this).apply {
            text = "Continue in your wallet"
            textSize = 22f
            gravity = Gravity.CENTER
            setTextColor(0xff261d35.toInt())
            setBackgroundColor(0xfffcfbfe.toInt())
        })
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                finishFailure(if (selected.dispatched) "OUTCOME_UNKNOWN" else "CANCELLED")
            }
        })
        lifecycleScope.launch {
            try {
                withTimeout(120_000L) { perform(selected) }
            } catch (error: Exception) {
                handleFailure(selected, error)
            }
        }
    }

    private suspend fun perform(selected: MobileWalletBridge.Request) {
        val adapter = MobileWalletBridge.connection()
        when (selected.method) {
            "connect" -> when (val result = adapter.connect(sender)) {
                is TransactionResult.Success -> {
                    val account = result.authResult.accounts.firstOrNull()
                        ?: throw MobileWalletFailure("MOBILE_WALLET_UNAVAILABLE")
                    if (account.publicKey.size != 32 ||
                        account.chains?.contains("solana:mainnet") == false) {
                        throw MobileWalletFailure("MOBILE_WALLET_ACCOUNT_CHANGED")
                    }
                    val address = MobileWalletWire.encode(account.publicKey)
                    if (!MobileWalletBridge.isCurrent(selected)) return
                    MobileWalletBridge.connected(address)
                    finishSuccess(mapOf("address" to address, "label" to account.accountLabel?.take(80)))
                }
                is TransactionResult.NoWalletFound -> finishFailure("NO_WALLET")
                is TransactionResult.Failure -> handleFailure(selected, result.e)
            }
            "disconnect" -> {
                // Always discard the local authorization, even when remote
                // revocation is declined. Pending transfer evidence survives.
                try { adapter.disconnect(sender) } finally {
                    if (MobileWalletBridge.isCurrent(selected)) MobileWalletBridge.forgetConnection()
                }
                finishSuccess(null)
            }
            "signAndSend" -> {
                val wire = selected.wire!!
                val versioned = MobileWalletWire.validate(wire, selected.address!!)
                val result = adapter.transact(sender) { auth ->
                    if (!MobileWalletBridge.isCurrent(selected)) throw MobileWalletFailure("MOBILE_WALLET_SESSION_LOST")
                    val account = auth.accounts.firstOrNull {
                        MobileWalletWire.encode(it.publicKey) == selected.address
                    } ?: throw MobileWalletFailure("MOBILE_WALLET_ACCOUNT_CHANGED")
                    if (account.chains?.contains("solana:mainnet") == false) {
                        throw MobileWalletFailure("MOBILE_WALLET_ACCOUNT_CHANGED")
                    }
                    val caps = getCapabilities()
                    val versionSupported = caps.supportedTransactionVersions.any {
                        if (versioned) it is Number && it.toInt() == 0 else it == "legacy"
                    }
                    // MWA 2 makes signAndSendTransaction mandatory. Its
                    // optional-features list must omit mandatory features;
                    // the deprecated SDK boolean can therefore be false for
                    // a fully compatible modern wallet. Check wire version,
                    // then invoke the mandatory method directly.
                    if (!versionSupported) throw MobileWalletFailure("MOBILE_WALLET_UNSUPPORTED_TRANSACTION")
                    MobileWalletBridge.markDispatched(selected)
                    signAndSendTransactions(arrayOf(wire), TransactionParams(
                        minContextSlot = null,
                        commitment = "confirmed",
                        skipPreflight = false,
                        maxRetries = 0,
                        waitForCommitmentToSendNextTransaction = true,
                    ))
                }
                when (result) {
                    is TransactionResult.Success -> {
                        val signatures = result.payload.signatures
                        if (signatures.size != 1 || signatures[0].size != 64) {
                            finishFailure("OUTCOME_UNKNOWN")
                            return
                        }
                        val signature = MobileWalletWire.encode(signatures[0])
                        MobileWalletBridge.saveSignature(selected, signature)
                        finishSuccess(mapOf("signature" to signature))
                    }
                    is TransactionResult.NoWalletFound -> finishFailure(
                        if (selected.dispatched) "OUTCOME_UNKNOWN" else "NO_WALLET",
                    )
                    is TransactionResult.Failure -> handleFailure(selected, result.e)
                }
            }
        }
    }

    private fun handleFailure(selected: MobileWalletBridge.Request, error: Exception) {
        if (completed) return
        val causes = generateSequence(error as Throwable?) { it.cause }.take(8).toList()
        val refused = causes.filterIsInstance<JsonRpc20Client.JsonRpc20RemoteException>()
            .any { it.code == ProtocolContract.ERROR_NOT_SIGNED }
        val code = MobileWalletOutcome.failure(
            dispatched = selected.dispatched,
            refused = refused,
            localCode = causes.filterIsInstance<MobileWalletFailure>().firstOrNull()?.code,
            timedOut = causes.any { it is TimeoutException || it is TimeoutCancellationException },
            cancelled = causes.any { it is CancellationException || it is InterruptedException },
        )
        if (selected.dispatched && code == "CANCELLED") {
            try { MobileWalletBridge.rejected(selected) }
            catch (_: Exception) {
                finishFailure("OUTCOME_UNKNOWN")
                return
            }
        }
        finishFailure(code)
    }

    private fun finishSuccess(value: Any?) {
        if (completed) return
        completed = true
        request?.let { MobileWalletBridge.complete(it, value) }
        finish()
    }

    private fun finishFailure(code: String) {
        if (completed) return
        completed = true
        request?.let { MobileWalletBridge.complete(it, error = "MOBILE_WALLET_$code") }
        finish()
    }

    override fun onDestroy() {
        if (!completed) request?.let {
            completed = true
            MobileWalletBridge.complete(it, error = if (it.dispatched) "MOBILE_WALLET_OUTCOME_UNKNOWN" else "MOBILE_WALLET_SESSION_LOST")
        }
        super.onDestroy()
    }
}
