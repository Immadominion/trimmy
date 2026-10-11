import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'incoming_funding_client.dart';
import 'incoming_funding_models.dart';
import 'incoming_funding_store.dart';
import 'mobile_wallet_service.dart';

enum IncomingFundingPhase {
  loading,
  disconnected,
  connecting,
  details,
  preparing,
  review,
  approving,
  pending,
  uncertain,
  confirmed,
  failed,
  invalidated,
}

class IncomingFundingController extends ChangeNotifier {
  IncomingFundingController({
    required this.client,
    required this.wallet,
    required this.store,
    required this.accountId,
    required this.subject,
    required this.recipient,
    this.allowNew = true,
    required this.isCurrent,
    required this.refreshPortfolio,
    DateTime Function()? now,
    this.pollInterval = const Duration(seconds: 30),
  }) : _now = now ?? DateTime.now;
  final IncomingFundingClient client;
  final MobileWalletService wallet;
  final FundingIntentStore store;
  final String accountId, subject, recipient;
  final bool Function() isCurrent;
  final Future<void> Function() refreshPortfolio;
  final DateTime Function() _now;
  final Duration pollInterval;
  final bool allowNew;
  IncomingFundingPhase phase = IncomingFundingPhase.loading;
  String? error, source, walletLabel;
  String? _candidateSignature;
  FundingReview? review;
  FundingIntent? _intent;
  MobileWalletPendingOperation? _nativePending;
  Timer? _poll, _expiry;
  int _epoch = 0;
  bool _closed = false, _invalidated = false, _busy = false, _foreground = true;
  bool get current => !_closed && !_invalidated && isCurrent();
  bool get busy => _busy;
  bool get checkingCandidate => _candidateSignature != null;
  bool get _ownsIntent =>
      _intent != null &&
      _intent!.accountId == accountId &&
      _intent!.subject == subject &&
      _intent!.recipient == recipient;
  String? get signature => _ownsIntent ? _intent?.signature : null;
  bool get canEdit =>
      allowNew &&
      current &&
      !_busy &&
      _intent == null &&
      _nativePending == null &&
      {
        IncomingFundingPhase.details,
        IncomingFundingPhase.review,
        IncomingFundingPhase.failed,
        IncomingFundingPhase.confirmed,
      }.contains(phase);
  bool get canConfirm =>
      current &&
      !_busy &&
      phase == IncomingFundingPhase.review &&
      review != null &&
      _now().toUtc().isBefore(review!.expiresAt);
  bool get canAcknowledge =>
      current &&
      !_busy &&
      phase == IncomingFundingPhase.uncertain &&
      signature == null &&
      _nativePending?.signature == null &&
      _ownsIntent &&
      (_nativePending == null ||
          _nativePending!.requestHash == _intent!.requestHash &&
              _nativePending!.address == _intent!.review.from);
  void _notify() {
    if (!_closed) notifyListeners();
  }

  void _check(int epoch) {
    if (!current || epoch != _epoch) {
      throw const FundingFailure('ACCOUNT_CHANGED');
    }
  }

  String _code(Object e) => e is FundingFailure
      ? e.code
      : e is MobileWalletException
      ? e.code
      : 'UNAVAILABLE';

  Future<void> initialize() async {
    if (_busy || !current) return;
    _busy = true;
    final epoch = _epoch;
    try {
      _intent = await store.read();
      _check(epoch);
      _nativePending = await wallet.getPendingOperation();
      _check(epoch);
      final intent = _intent;
      if (intent != null &&
          intent.accountId == accountId &&
          intent.subject == subject &&
          intent.recipient == recipient) {
        await intent.review.validate(
          expectedFrom: intent.review.from,
          expectedRecipient: recipient,
          expectedAsset: intent.review.asset,
          expectedAmount: intent.review.amountRaw,
          now: _now(),
          allowExpired: true,
        );
        _check(epoch);
        review = intent.review;
        source = intent.review.from;
        final sig = _nativePending?.signature;
        if (_nativePending?.requestHash == intent.requestHash && sig != null) {
          _intent = intent.withSignature(sig);
          await store.save(_intent!);
          _check(epoch);
        }
        phase = signature == null
            ? IncomingFundingPhase.uncertain
            : IncomingFundingPhase.pending;
      } else if (intent != null || _nativePending != null) {
        // An account switch cannot adopt another account's funding details.
        phase = IncomingFundingPhase.uncertain;
        error = 'PENDING_OTHER_ACCOUNT';
      } else {
        phase = IncomingFundingPhase.disconnected;
      }
    } catch (e) {
      if (current) {
        phase = IncomingFundingPhase.uncertain;
        error = _code(e);
      }
    } finally {
      _busy = false;
      _notify();
    }
    if (phase == IncomingFundingPhase.pending) unawaited(checkStatus());
  }

  Future<void> connect() async {
    if (!allowNew ||
        !current ||
        _busy ||
        _intent != null ||
        _nativePending != null) {
      return;
    }
    _busy = true;
    error = null;
    phase = IncomingFundingPhase.connecting;
    _notify();
    final epoch = _epoch;
    try {
      final selected = await wallet.connect();
      _check(epoch);
      if (!fundingAddress(selected.address) || selected.address == recipient) {
        throw const FundingFailure('SOURCE_IS_DESTINATION');
      }
      source = selected.address;
      walletLabel = selected.label;
      phase = IncomingFundingPhase.details;
    } catch (e) {
      if (current) {
        error = _code(e);
        phase = IncomingFundingPhase.disconnected;
      }
    } finally {
      _busy = false;
      _notify();
    }
  }

  void edit() {
    if (!canEdit) return;
    _expiry?.cancel();
    review = null;
    error = null;
    phase = IncomingFundingPhase.details;
    _notify();
  }

  Future<void> prepare(String asset, String amount) async {
    if (!canEdit || source == null) return;
    final raw = fundingAmountRaw(amount, asset);
    if (raw == null) {
      error = 'INVALID_AMOUNT';
      _notify();
      return;
    }
    _busy = true;
    error = null;
    review = null;
    phase = IncomingFundingPhase.preparing;
    _notify();
    final epoch = _epoch, from = source!;
    try {
      final next = await client.preview(from, asset, raw);
      _check(epoch);
      await next.validate(
        expectedFrom: from,
        expectedRecipient: recipient,
        expectedAsset: asset,
        expectedAmount: raw,
        now: _now(),
      );
      _check(epoch);
      review = next;
      phase = IncomingFundingPhase.review;
      _expiry?.cancel();
      _expiry = Timer(next.expiresAt.difference(_now().toUtc()), () {
        if (current &&
            epoch == _epoch &&
            phase == IncomingFundingPhase.review) {
          review = null;
          phase = IncomingFundingPhase.details;
          error = 'REVIEW_EXPIRED';
          _notify();
        }
      });
    } catch (e) {
      if (current) {
        error = _code(e);
        phase = IncomingFundingPhase.details;
      }
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> confirm() async {
    if (!canConfirm) return;
    final approved = review!, epoch = _epoch;
    _busy = true;
    error = null;
    phase = IncomingFundingPhase.approving;
    _expiry?.cancel();
    _notify();
    var dispatched = false;
    try {
      await approved.validate(
        expectedFrom: source!,
        expectedRecipient: recipient,
        expectedAsset: approved.asset,
        expectedAmount: approved.amountRaw,
        now: _now(),
      );
      _check(epoch);
      final hash = (await Sha256().hash(
        base64Decode(approved.transaction),
      )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      _check(epoch);
      final intent = FundingIntent(
        accountId: accountId,
        subject: subject,
        recipient: recipient,
        requestHash: hash,
        review: approved,
      );
      await store.save(intent);
      _intent = intent;
      _check(epoch);
      // Recheck expiry after storage, before a wallet can broadcast.
      if (!_now().toUtc().isBefore(approved.expiresAt)) {
        throw const FundingFailure('REVIEW_EXPIRED');
      }
      dispatched = true;
      final sig = await wallet.signAndSend(
        address: source!,
        unsignedTransaction: approved.transaction,
      );
      // Persist even if a logout occurred while the external wallet was open.
      // Persistence allows reconciliation; it never signs or submits again.
      if (!fundingSignature(sig)) throw const FundingFailure('OUTCOME_UNKNOWN');
      _intent = intent.withSignature(sig);
      await store.save(_intent!);
      _check(epoch);
      phase = IncomingFundingPhase.pending;
    } catch (e) {
      final code = _code(e);
      final safe =
          !dispatched ||
          {
            'MOBILE_WALLET_CANCELLED',
            'MOBILE_WALLET_NOT_CONNECTED',
            'MOBILE_WALLET_ACCOUNT_CHANGED',
            'MOBILE_WALLET_INVALID_TRANSACTION',
            'MOBILE_WALLET_UNSUPPORTED_TRANSACTION',
            'MOBILE_WALLET_NO_WALLET',
            'MOBILE_WALLET_UNSUPPORTED',
          }.contains(code);
      if (safe && _intent != null) {
        try {
          await store.clear(_intent!.requestHash);
          _intent = null;
        } catch (_) {
          /* Keep journal on uncertain storage. */
        }
      }
      if (current) {
        error = code;
        if (_intent == null) source = null;
        phase = _intent == null
            ? IncomingFundingPhase.disconnected
            : signature == null
            ? IncomingFundingPhase.uncertain
            : IncomingFundingPhase.pending;
        review = _intent?.review;
      }
    } finally {
      _busy = false;
      _notify();
    }
    if (current && phase == IncomingFundingPhase.pending) {
      unawaited(checkStatus());
    }
  }

  Future<void> checkStatus() async {
    final intent = _intent;
    final checkingSignature = intent?.signature ?? _candidateSignature;
    if (!current ||
        _busy ||
        !_foreground ||
        checkingSignature == null ||
        intent!.accountId != accountId ||
        intent.subject != subject ||
        intent.recipient != recipient) {
      return;
    }
    _busy = true;
    _poll?.cancel();
    _notify();
    final epoch = _epoch;
    try {
      final result = await client.status(intent.review, checkingSignature);
      _check(epoch);
      if (result.status == FundingStatus.pending) {
        phase = intent.signature == null
            ? IncomingFundingPhase.uncertain
            : IncomingFundingPhase.pending;
      } else {
        if (intent.signature == null) {
          final verified = intent.withSignature(checkingSignature);
          await store.save(verified);
          _check(epoch);
          _intent = verified;
        }
        // Only a server-verified exact message/signature resolves the journal.
        await wallet.resolvePending(
          requestHash: intent.requestHash,
          signature: checkingSignature,
        );
        _check(epoch);
        await store.clear(intent.requestHash);
        _check(epoch);
        _intent = null;
        _nativePending = null;
        _candidateSignature = null;
        phase = result.status == FundingStatus.confirmed
            ? IncomingFundingPhase.confirmed
            : IncomingFundingPhase.failed;
        error = result.status == FundingStatus.failed
            ? 'TRANSFER_FAILED'
            : null;
        if (result.status == FundingStatus.confirmed) {
          try {
            await refreshPortfolio();
          } catch (_) {
            /* Receipt remains true; balance can catch up. */
          }
          _check(epoch);
        }
      }
    } catch (e) {
      if (current) {
        error = _code(e);
        if (intent.signature == null &&
            {'INVALID_REVIEW', 'INVALID_SIGNATURE'}.contains(error)) {
          _candidateSignature = null;
        }
        phase = intent.signature == null
            ? IncomingFundingPhase.uncertain
            : IncomingFundingPhase.pending;
      }
    } finally {
      _busy = false;
      _notify();
    }
    if (current &&
        (phase == IncomingFundingPhase.pending ||
            _candidateSignature != null) &&
        _foreground) {
      _poll = Timer(
        error == null ? pollInterval : const Duration(seconds: 60),
        () => unawaited(checkStatus()),
      );
    }
  }

  /// A wallet can show its signature even when its handoff was interrupted.
  Future<void> reconcileSignature(String value) async {
    if (!current ||
        _busy ||
        phase != IncomingFundingPhase.uncertain ||
        _intent == null ||
        _intent!.accountId != accountId ||
        _intent!.subject != subject ||
        _intent!.recipient != recipient) {
      return;
    }
    if (!fundingSignature(value)) {
      error = 'INVALID_SIGNATURE';
      _notify();
      return;
    }
    // A pasted ID is untrusted until the API verifies the exact reviewed wire.
    // Keep it ephemeral and editable if it is absent or unrelated on chain.
    _candidateSignature = value;
    error = null;
    await checkStatus();
  }

  Future<void> acknowledgeUnknown() async {
    if (!canAcknowledge) return;
    _busy = true;
    final epoch = _epoch;
    try {
      final pending = await wallet.getPendingOperation();
      _check(epoch);
      if (pending?.signature != null ||
          pending != null &&
              (pending.requestHash != _intent?.requestHash ||
                  pending.address != _intent?.review.from)) {
        throw const FundingFailure('PENDING_TRANSFER');
      }
      _poll?.cancel();
      if (pending != null) {
        await wallet.acknowledgeUnknownOutcome(
          requestHash: pending.requestHash,
        );
        _check(epoch);
      }
      if (_intent != null) {
        await store.clear(_intent!.requestHash);
        _check(epoch);
      }
      _intent = null;
      _nativePending = null;
      _candidateSignature = null;
      review = null;
      source = null;
      error = null;
      phase = IncomingFundingPhase.disconnected;
    } catch (e) {
      if (current) error = _code(e);
    } finally {
      _busy = false;
      _notify();
    }
  }

  void setForeground(bool value) {
    _foreground = value;
    if (!value) {
      _poll?.cancel();
    } else if (phase == IncomingFundingPhase.pending ||
        _candidateSignature != null) {
      unawaited(checkStatus());
    }
    // Launching the approving wallet naturally backgrounds Trimmy. Do not cancel it.
  }

  void invalidate() {
    if (_closed || _invalidated) return;
    _invalidated = true;
    _epoch++;
    _poll?.cancel();
    _expiry?.cancel();
    client.close();
    phase = IncomingFundingPhase.invalidated;
    _notify();
  }

  @override
  void dispose() {
    if (_closed) return;
    invalidate();
    _closed = true;
    super.dispose();
  }
}
