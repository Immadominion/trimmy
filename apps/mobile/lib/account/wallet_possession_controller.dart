import 'dart:async';

import 'package:flutter/foundation.dart';

import '../practice_sync/protocol.dart';
import 'account_data_models.dart';
import 'wallet_possession_client.dart';
import 'wallet_possession_signer.dart';

enum WalletPossessionPhase {
  idle,
  preparing,
  reviewing,
  signing,
  submitting,
  verified,
  expired,
  cancelled,
  error,
  closed,
}

/// One account's explicit message-proof flow. Preparing never signs. Only
/// confirm() can invoke the signer, and every asynchronous boundary checks the
/// account generation again. No signature or challenge is persisted here.
class WalletPossessionController extends ChangeNotifier {
  WalletPossessionController({
    required WalletPossessionClient client,
    required this._signer,
    required this.subject,
    required this._readContext,
    required this._isAccountCurrent,
    this._cancelContext,
    this._closeContext,
    DateTime Function()? now,
    Duration operationTimeout = const Duration(seconds: 90),
  }) : _client = client,
       _now = now ?? DateTime.now,
       _operationTimeout = operationTimeout {
    if (subject.isEmpty ||
        subject.length > 256 ||
        subject.trim() != subject ||
        normalizePracticeUuid(client.accountId) != client.accountId ||
        operationTimeout <= Duration.zero ||
        operationTimeout > const Duration(minutes: 2)) {
      throw const WalletPossessionException(
        WalletPossessionFailure.invalidConfiguration,
      );
    }
  }

  final WalletPossessionClient _client;
  final WalletPossessionSigner _signer;
  final String subject;
  final Future<AccountContextSnapshot> Function() _readContext;
  final bool Function() _isAccountCurrent;
  final void Function()? _cancelContext, _closeContext;
  final DateTime Function() _now;
  final Duration _operationTimeout;
  WalletPossessionPhase _phase = WalletPossessionPhase.idle;
  WalletPossessionFailure? _failure;
  WalletPossessionChallenge? _challenge;
  WalletPossessionReceipt? _receipt;
  Timer? _expiryTimer;
  Completer<void>? _stop;
  int _generation = 0;
  bool _foreground = true, _online = true, _closed = false;

  String get accountId => _client.accountId;
  WalletPossessionPhase get phase =>
      _phase == WalletPossessionPhase.reviewing && _challenge!.isExpired(_now())
      ? WalletPossessionPhase.expired
      : _phase;
  WalletPossessionFailure? get failure => _failure;
  WalletPossessionChallenge? get challenge => _challenge;
  WalletPossessionReceipt? get receipt => _receipt;
  bool get isBusy => const {
    WalletPossessionPhase.preparing,
    WalletPossessionPhase.signing,
    WalletPossessionPhase.submitting,
  }.contains(_phase);
  bool get canStart =>
      !_closed && !isBusy && _foreground && _online && _isAccountCurrent();
  bool get canSign => canStart && phase == WalletPossessionPhase.reviewing;

  bool _current(int generation) =>
      !_closed &&
      generation == _generation &&
      _foreground &&
      _online &&
      _isAccountCurrent();

  void _notify() {
    if (!_closed) notifyListeners();
  }

  void _check(int generation) {
    if (!_current(generation)) {
      throw const WalletPossessionException(WalletPossessionFailure.cancelled);
    }
  }

  int _begin(WalletPossessionPhase phase) {
    _expiryTimer?.cancel();
    _stop = Completer<void>();
    _phase = phase;
    _failure = null;
    _receipt = null;
    final generation = ++_generation;
    _notify();
    return generation;
  }

  Future<T> _bounded<T>(Future<T> work) =>
      Future.any([
        work,
        _stop!.future.then<T>((_) {
          throw const WalletPossessionException(
            WalletPossessionFailure.cancelled,
          );
        }),
      ]).timeout(
        _operationTimeout,
        onTimeout: () => throw const WalletPossessionException(
          WalletPossessionFailure.timeout,
        ),
      );

  void _fail(Object error) {
    _expiryTimer?.cancel();
    _client.cancelPending();
    _cancelContext?.call();
    _challenge = null;
    _receipt = null;
    _phase = WalletPossessionPhase.error;
    _failure = switch (error) {
      WalletPossessionException(:final failure) => failure,
      AccountDataException(:final failure) => switch (failure) {
        AccountDataFailure.unauthenticated =>
          WalletPossessionFailure.unauthenticated,
        AccountDataFailure.accountMismatch =>
          WalletPossessionFailure.accountMismatch,
        AccountDataFailure.walletMissing =>
          WalletPossessionFailure.walletMissing,
        AccountDataFailure.walletAmbiguous =>
          WalletPossessionFailure.walletAmbiguous,
        AccountDataFailure.timeout => WalletPossessionFailure.timeout,
        AccountDataFailure.notConfigured =>
          WalletPossessionFailure.notConfigured,
        _ => WalletPossessionFailure.unavailable,
      },
      _ => WalletPossessionFailure.unavailable,
    };
    _notify();
  }

  /// Refresh the account's linked wallet and obtain a reviewable challenge.
  /// This method performs no signing and must follow a person's explicit tap.
  Future<void> prepare() async {
    if (!canStart) return;
    _challenge = null;
    final generation = _begin(WalletPossessionPhase.preparing);
    try {
      _check(generation);
      final context = await _bounded(_readContext());
      _check(generation);
      if (context.userId != accountId) {
        throw const WalletPossessionException(
          WalletPossessionFailure.accountMismatch,
        );
      }
      final wallet = context.embeddedSolanaWallet;
      if (wallet.status != EmbeddedSolanaWalletStatus.candidate) {
        throw WalletPossessionException(
          wallet.status == EmbeddedSolanaWalletStatus.missing
              ? WalletPossessionFailure.walletMissing
              : WalletPossessionFailure.walletAmbiguous,
        );
      }
      final challenge = await _bounded(
        _client.issueChallenge(expectedWalletAddress: wallet.address!),
      );
      _check(generation);
      if (challenge.accountId != accountId ||
          challenge.walletAddress != wallet.address) {
        throw const WalletPossessionException(
          WalletPossessionFailure.accountMismatch,
        );
      }
      if (challenge.isExpired(_now())) {
        throw const WalletPossessionException(
          WalletPossessionFailure.challengeExpired,
        );
      }
      _challenge = challenge;
      _phase = WalletPossessionPhase.reviewing;
      _expiryTimer = Timer(challenge.expiresAt.difference(_now().toUtc()), () {
        if (_current(generation) && _phase == WalletPossessionPhase.reviewing) {
          _phase = WalletPossessionPhase.expired;
          _notify();
        }
      });
      _notify();
    } catch (error) {
      if (_current(generation)) _fail(error);
    }
  }

  /// The explicit "Sign message" action. Re-entering this method, navigation,
  /// logout or a delayed native result cannot submit another account's proof.
  Future<void> confirm() async {
    if (!canSign) return;
    final challenge = _challenge!;
    final generation = _begin(WalletPossessionPhase.signing);
    try {
      _check(generation);
      final signature = await _bounded(
        _signer.sign(expectedSubject: subject, challenge: challenge),
      );
      _check(generation);
      if (challenge.isExpired(_now())) {
        throw const WalletPossessionException(
          WalletPossessionFailure.challengeExpired,
        );
      }
      _phase = WalletPossessionPhase.submitting;
      _notify();
      _check(generation);
      final receipt = await _bounded(
        _client.verify(challenge: challenge, signature: signature),
      );
      _check(generation);
      if (receipt.accountId != accountId ||
          receipt.walletAddress != challenge.walletAddress ||
          receipt.network != challenge.network ||
          receipt.challengeId != challenge.challengeId) {
        throw const WalletPossessionException(
          WalletPossessionFailure.invalidResponse,
        );
      }
      _challenge = null;
      _receipt = receipt;
      _phase = WalletPossessionPhase.verified;
      _notify();
    } catch (error) {
      if (_current(generation)) _fail(error);
    }
  }

  void cancel() {
    if (_closed) return;
    _generation++;
    _expiryTimer?.cancel();
    if (_stop case final stop? when !stop.isCompleted) stop.complete();
    _client.cancelPending();
    _cancelContext?.call();
    _challenge = null;
    _receipt = null;
    _failure = null;
    _phase = WalletPossessionPhase.cancelled;
    _notify();
  }

  void setForeground(bool foreground) {
    if (_closed || foreground == _foreground) return;
    _foreground = foreground;
    if (!foreground && (isBusy || _phase == WalletPossessionPhase.reviewing)) {
      cancel();
    } else {
      _notify();
    }
  }

  void setNetworkAvailable(bool available) {
    if (_closed || available == _online) return;
    _online = available;
    if (!available && (isBusy || _phase == WalletPossessionPhase.reviewing)) {
      cancel();
    } else {
      _notify();
    }
  }

  @override
  void dispose() {
    if (_closed) return;
    cancel();
    _closed = true;
    _phase = WalletPossessionPhase.closed;
    _client.close();
    _closeContext?.call();
    super.dispose();
  }
}
