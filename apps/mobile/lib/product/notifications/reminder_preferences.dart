import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../market/http_paper_order_repository.dart' show paperUuidV4;
import '../onboarding/onboarding_models.dart';
import '../workdays/workdays.dart';
import 'notification_permission.dart';

class ReminderPreferenceChanged implements Exception {}

class ReminderState {
  const ReminderState(
    this.frequency,
    this.revision,
    this.mutationId,
    this.permission,
  );
  final String? frequency, mutationId;
  final int revision;
  final String permission;
  String encode() => jsonEncode({
    'frequency': frequency,
    'revision': revision,
    'mutationId': mutationId,
    'permission': permission,
  });
}

enum ReminderPreference {
  daily('On workdays', 'Around 7 PM, when work is waiting.'),
  occasional('A few times a week', 'Mon, Wed and Fri, around 7 PM.'),
  off('Keep it quiet', 'I’ll come back on my own.');

  const ReminderPreference(this.label, this.caption);
  final String label, caption;
}

class ReminderPreferences {
  static String _key(String principal) => 'trimmy.reminders.v1.$principal';
  static ReminderPreference? read(
    SharedPreferences preferences,
    String principal,
  ) {
    // A damaged cache must not crash Settings or revive an older opt-in.
    ReminderState? state;
    try {
      state = stored(preferences, principal);
    } catch (_) {
      return null;
    }
    final value = state != null
        ? state.frequency
        : preferences.getString(_key(principal));
    for (final item in ReminderPreference.values) {
      if (item.name == value) return item;
    }
    return null;
  }

  static Future<void> save(
    SharedPreferences preferences,
    String principal,
    ReminderPreference value,
    OnboardingNotificationStatus permission,
  ) async {
    ReminderState? prior;
    try {
      prior = stored(preferences, principal);
    } catch (_) {
      // An explicit choice can repair a damaged cache. Revision zero cannot
      // overwrite an existing server choice without conflict handling.
    }
    await write(
      preferences,
      principal,
      ReminderState(
        value.name,
        prior?.revision ?? 0,
        prior?.mutationId != null && prior?.frequency == value.name
            ? prior!.mutationId
            : paperUuidV4(),
        permission.name,
      ),
    );
  }

  static String snapshot(SharedPreferences preferences, String principal) =>
      preferences.getString('${_key(principal)}.sync') ??
      preferences.getString(_key(principal)) ??
      '';

  static ReminderState? stored(
    SharedPreferences preferences,
    String principal,
  ) {
    final raw = preferences.getString('${_key(principal)}.sync');
    if (raw == null) return null;
    final value = jsonDecode(raw);
    if (value is! Map ||
        value.length != 4 ||
        !value.keys.toSet().containsAll([
          'frequency',
          'revision',
          'mutationId',
          'permission',
        ]) ||
        ![null, 'daily', 'occasional', 'off'].contains(value['frequency']) ||
        value['revision'] is! int ||
        value['revision'] < 0 ||
        value['revision'] > 9007199254740991 ||
        value['permission'] is! String ||
        value['mutationId'] != null &&
            (value['mutationId'] is! String ||
                !RegExp(
                  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
                ).hasMatch(value['mutationId'])) ||
        value['frequency'] == null &&
            (value['revision'] != 0 || value['mutationId'] != null)) {
      throw StateError('REMINDER_STORAGE_INVALID');
    }
    return ReminderState(
      value['frequency'],
      value['revision'],
      value['mutationId'],
      value['permission'],
    );
  }

  static Future<void> write(
    SharedPreferences preferences,
    String principal,
    ReminderState state,
  ) async {
    final key = '${_key(principal)}.sync';
    final before = preferences.getString(key), encoded = state.encode();
    try {
      if (!await preferences.setString(key, encoded)) {
        throw StateError('REMINDER_PREFERENCE_NOT_SAVED');
      }
    } catch (_) {
      // SharedPreferences mutates its cache before platform persistence succeeds.
      // Restore only our own failed write, never a newer local choice.
      if (preferences.getString(key) == encoded) {
        try {
          if (before == null) {
            await preferences.remove(key);
          } else {
            await preferences.setString(key, before);
          }
        } catch (_) {
          /* The next explicit save can retry storage. */
        }
      }
      rethrow;
    }
  }

  /// Reconciles the active profile without displaying an OS permission prompt.
  /// A previous denial may have been changed in system Settings since saving.
  static Future<bool> sync(
    SharedPreferences preferences,
    String? principal, {
    WorkJourney? journey,
  }) => ProductNotificationPermission.setReminder(
    principal == null
        ? ReminderPreference.off.name
        : (read(preferences, principal) ?? ReminderPreference.off).name,
    journey: journey,
  );
}
