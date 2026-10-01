import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../account/guest_session.dart';
import '../market/http_paper_order_repository.dart' show paperUuidV4;
import 'reminder_preferences.dart';

/// Account preference only. OS permission stays local and is never requested here.
class ReminderPreferenceSync {
  ReminderPreferenceSync(this.preferences, this.client, this.baseUri) {
    if (baseUri.scheme != 'https' ||
        baseUri.host.isEmpty ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment ||
        !['', '/'].contains(baseUri.path)) {
      throw ArgumentError('REMINDER_ORIGIN_INVALID');
    }
  }
  final SharedPreferences preferences;
  final http.Client client;
  final Uri baseUri;
  final Map<String, Future<void>> _active = {};

  Future<void> sync(
    String principal,
    Future<PaperAuthorization> Function() authorization,
    bool Function() current,
  ) {
    final prior = _active[principal];
    if (prior != null) {
      return prior.catchError((Object _) {}).then((_) async {
        if (current()) await sync(principal, authorization, current);
      });
    }
    late final Future<void> operation;
    operation = _sync(principal, authorization, current).whenComplete(() {
      if (identical(_active[principal], operation)) _active.remove(principal);
    });
    _active[principal] = operation;
    return operation;
  }

  Future<void> _sync(
    String principal,
    Future<PaperAuthorization> Function() authorization,
    bool Function() current,
  ) async {
    var snapshot = ReminderPreferences.snapshot(preferences, principal);
    void check() {
      if (!current() ||
          ReminderPreferences.snapshot(preferences, principal) != snapshot) {
        throw StateError('REMINDER_IDENTITY_CHANGED');
      }
    }

    Future<void> persist(ReminderState value) async {
      check();
      await ReminderPreferences.write(preferences, principal, value);
      // SharedPreferences writes update the local cache before awaiting platform storage.
      snapshot = value.encode();
      check();
    }

    check();
    var remote = await _request('GET', authorization, current);
    check();
    var local = ReminderPreferences.stored(preferences, principal);
    if (local == null) {
      var choice = ReminderPreferences.read(preferences, principal)?.name;
      final alias = remote['claimedGuestId'] as String?;
      if (choice == null && alias != null && alias != principal) {
        final guest = ReminderPreferences.stored(preferences, alias);
        // The alias comes only from the authenticated server's successful claim.
        // A previously explicit account opt-out is never replaced by guest opt-in.
        if (guest?.mutationId != null &&
            !(remote['frequency'] == 'off' && guest!.frequency != 'off')) {
          local = guest;
        } else if (remote['revision'] == 0) {
          choice = ReminderPreferences.read(preferences, alias)?.name;
        }
      }
      if (local == null && choice != null && remote['revision'] == 0) {
        local = ReminderState(choice, 0, paperUuidV4(), 'notRequested');
      }
      if (local != null) await persist(local);
    }
    if (local?.mutationId != null) {
      remote = await _request('PUT', authorization, current, local);
      check();
      if (remote['conflict'] == true && local!.frequency == 'off') {
        // An offline opt-out may rebase once. An opt-in never does this.
        local = ReminderState(
          'off',
          remote['revision'] as int,
          paperUuidV4(),
          local.permission,
        );
        await persist(local);
        remote = await _request('PUT', authorization, current, local);
        check();
        if (remote['conflict'] == true) {
          throw StateError('REMINDER_SYNC_UNAVAILABLE');
        }
      } else if (remote['conflict'] == true) {
        await persist(
          ReminderState(
            remote['frequency'] as String?,
            remote['revision'] as int,
            null,
            local!.permission,
          ),
        );
        throw ReminderPreferenceChanged();
      }
    }
    await persist(
      ReminderState(
        remote['frequency'] as String?,
        remote['revision'] as int,
        null,
        local?.permission ?? 'notRequested',
      ),
    );
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Future<PaperAuthorization> Function() authorization,
    bool Function() current, [
    ReminderState? state,
  ]) async {
    Future<Map<String, dynamic>> read() async {
      if (!current()) throw StateError('REMINDER_IDENTITY_CHANGED');
      final auth = await authorization();
      if (!current()) throw StateError('REMINDER_IDENTITY_CHANGED');
      final request =
          http.Request(
              method,
              baseUri.replace(path: '/v1/notifications/reminder-preferences'),
            )
            ..followRedirects = false
            ..headers.addAll({
              'authorization': auth.headerValue,
              'accept': 'application/json',
            });
      if (state != null) {
        request.headers['content-type'] = 'application/json';
        request.body = jsonEncode({
          'mutationId': state.mutationId,
          'baseRevision': state.revision,
          'frequency': state.frequency,
        });
      }
      final response = await client.send(request);
      if (!current() ||
          ![200, 409].contains(response.statusCode) ||
          response.headers['content-type']?.split(';').first.trim() !=
              'application/json') {
        await response.stream.listen((_) {}).cancel();
        throw StateError('REMINDER_SYNC_UNAVAILABLE');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > 4096) {
          throw StateError('REMINDER_RESPONSE_INVALID');
        }
        bytes.addAll(chunk);
      }
      if (!current()) throw StateError('REMINDER_IDENTITY_CHANGED');
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map<String, dynamic> ||
          data.length != (method == 'GET' ? 4 : 5) ||
          !data.keys.toSet().containsAll([
            'schemaVersion',
            'revision',
            'frequency',
            'claimedGuestId',
            if (method == 'PUT') 'conflict',
          ]) ||
          data['schemaVersion'] != 1 ||
          data['revision'] is! int ||
          data['revision'] < 0 ||
          data['revision'] > 9007199254740991 ||
          ![null, 'daily', 'occasional', 'off'].contains(data['frequency']) ||
          (data['revision'] == 0) != (data['frequency'] == null) ||
          data['claimedGuestId'] != null &&
              (data['claimedGuestId'] is! String ||
                  !RegExp(
                    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
                  ).hasMatch(data['claimedGuestId'])) ||
          method == 'PUT' && data['conflict'] != (response.statusCode == 409) ||
          method == 'GET' && response.statusCode != 200) {
        throw StateError('REMINDER_RESPONSE_INVALID');
      }
      return data;
    }

    return read().timeout(const Duration(seconds: 12));
  }
}
