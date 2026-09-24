import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../account/guest_session.dart';
import 'career_repository.dart';
import 'career_activity_week.dart';

/// Keeps one server-owned Career record bound to one paper principal.
///
/// A previous account's late response is ignored after an identity switch.
/// Transient refresh failures retain the last confirmed summary and mark it
/// stale, while a first-load failure never creates local Career numbers.
final class CareerController extends ChangeNotifier {
  CareerRepository? _repository;
  String? _principalKey;
  CareerSummary? _summary;
  CareerFailure? _failure;
  GuestSessionFailure? _guestSessionFailure;
  bool _loading = false;
  bool _refreshQueued = false;
  bool _disposed = false;
  int _generation = 0;

  Future<CareerActivityWeek?> activityWeek() async {
    final repository = _repository;
    final generation = _generation;
    if (_disposed || repository is! CareerActivityWeekReader) return null;
    final week = await (repository as CareerActivityWeekReader)
        .getActivityWeek();
    return _disposed || generation != _generation ? null : week;
  }

  String? get principalKey => _principalKey;
  CareerSummary? get summary => _summary;
  CareerFailure? get failure => _failure;
  GuestSessionFailure? get guestSessionFailure => _guestSessionFailure;
  bool get loading => _loading;
  bool get hasConfirmedSummary => _summary != null;
  bool get stale => _summary != null && _failure != null;

  Future<void> bind({
    required String principalKey,
    required CareerRepository repository,
  }) async {
    if (_disposed || principalKey.isEmpty) return;
    if (_principalKey == principalKey && identical(_repository, repository)) {
      await refresh();
      return;
    }
    _generation++;
    _principalKey = principalKey;
    _repository = repository;
    _summary = null;
    _failure = null;
    _guestSessionFailure = null;
    _loading = false;
    _refreshQueued = false;
    notifyListeners();
    await refresh();
  }

  void unbind() {
    if (_disposed) return;
    _generation++;
    _principalKey = null;
    _repository = null;
    _summary = null;
    _failure = null;
    _guestSessionFailure = null;
    _loading = false;
    _refreshQueued = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    final repository = _repository;
    final principalKey = _principalKey;
    if (_disposed || repository == null || principalKey == null) return;
    if (_loading) {
      _refreshQueued = true;
      return;
    }
    final generation = _generation;
    _loading = true;
    notifyListeners();
    try {
      final summary = await repository.getSummary();
      if (!_owns(generation, principalKey, repository)) return;
      _summary = summary;
      _failure = null;
      _guestSessionFailure = null;
    } on GuestSessionException catch (error) {
      if (!_owns(generation, principalKey, repository)) return;
      _failure = null;
      _guestSessionFailure = error.failure;
    } on CareerException catch (error) {
      if (!_owns(generation, principalKey, repository)) return;
      _failure = error.failure;
      _guestSessionFailure = null;
    } catch (_) {
      if (!_owns(generation, principalKey, repository)) return;
      _failure = CareerFailure.unavailable;
      _guestSessionFailure = null;
    } finally {
      if (_owns(generation, principalKey, repository)) {
        _loading = false;
        final again = _refreshQueued;
        _refreshQueued = false;
        notifyListeners();
        if (again) unawaited(refresh());
      }
    }
  }

  String get message => switch (_failure) {
    CareerFailure.offline =>
      'Your career is offline. Check your connection and try again.',
    CareerFailure.timeout => 'Your career took too long to open. Try again.',
    CareerFailure.accountRequired =>
      'Your career needs a fresh session. Try again.',
    CareerFailure.rateLimited =>
      'Your career is refreshing too quickly. Try again shortly.',
    CareerFailure.profileRequired =>
      'Finish setting up your Trimmy profile, then try again.',
    _ => 'Your career is unavailable. Try again.',
  };

  bool _owns(
    int generation,
    String principalKey,
    CareerRepository repository,
  ) =>
      !_disposed &&
      generation == _generation &&
      _principalKey == principalKey &&
      identical(_repository, repository);

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _repository = null;
    _principalKey = null;
    _summary = null;
    _guestSessionFailure = null;
    super.dispose();
  }
}
