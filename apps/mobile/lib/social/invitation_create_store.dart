import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'invitation.dart';

final _invitationUuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _invitationInstant = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
);

@immutable
final class InvitationCreateCommand {
  factory InvitationCreateCommand({
    required String mutationId,
    required DateTime expiresAt,
  }) {
    final instant = expiresAt.toUtc();
    final encoded = instant.toIso8601String();
    if (_invitationUuid.firstMatch(mutationId)?.group(0) != mutationId ||
        !_invitationInstant.hasMatch(encoded) ||
        DateTime.tryParse(encoded)?.toUtc().toIso8601String() != encoded) {
      throw const InvitationException(InvitationFailure.invalidRequest);
    }
    return InvitationCreateCommand._(
      mutationId: mutationId,
      expiresAt: instant,
    );
  }

  const InvitationCreateCommand._({
    required this.mutationId,
    required this.expiresAt,
  });

  final String mutationId;
  final DateTime expiresAt;

  Map<String, Object> toJson() => {
    'schemaVersion': 1,
    'mutationId': mutationId,
    'expiresAt': expiresAt.toIso8601String(),
  };

  static InvitationCreateCommand fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value.length != 3 ||
        value['schemaVersion'] != 1 ||
        value['mutationId'] is! String ||
        value['expiresAt'] is! String) {
      throw const InvitationException(InvitationFailure.invalidResponse);
    }
    final expiresAt = DateTime.tryParse(value['expiresAt'] as String);
    if (expiresAt == null) {
      throw const InvitationException(InvitationFailure.invalidResponse);
    }
    try {
      return InvitationCreateCommand(
        mutationId: value['mutationId'] as String,
        expiresAt: expiresAt,
      );
    } on InvitationException {
      throw const InvitationException(InvitationFailure.invalidResponse);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is InvitationCreateCommand &&
      other.mutationId == mutationId &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(mutationId, expiresAt);
}

abstract interface class InvitationCreateMutationStore {
  Future<InvitationCreateCommand?> read(String accountId);
  Future<bool> write(String accountId, InvitationCreateCommand command);
  Future<bool> remove(String accountId, InvitationCreateCommand command);
}

/// Stores only a public idempotency UUID and expiry, never credentials or an X
/// subject. Keeping the exact command prevents a commit-then-timeout retry from
/// creating a second invitation.
final class PreferencesInvitationCreateMutationStore
    implements InvitationCreateMutationStore {
  const PreferencesInvitationCreateMutationStore(this._preferences);

  static const _prefix = 'trimmy.social.pending-invitation-create.v1.';
  final SharedPreferences _preferences;

  String _key(String accountId) => '$_prefix$accountId';

  @override
  Future<InvitationCreateCommand?> read(String accountId) async {
    try {
      await _preferences.reload();
      final encoded = _preferences.getString(_key(accountId));
      if (encoded == null) return null;
      return InvitationCreateCommand.fromJson(jsonDecode(encoded));
    } catch (_) {
      throw const InvitationException(InvitationFailure.unavailable);
    }
  }

  @override
  Future<bool> write(String accountId, InvitationCreateCommand command) async {
    try {
      final existing = await read(accountId);
      if (existing != null && existing != command) return false;
      if (existing == command) return true;
      return await _preferences.setString(
        _key(accountId),
        jsonEncode(command.toJson()),
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> remove(String accountId, InvitationCreateCommand command) async {
    try {
      final existing = await read(accountId);
      if (existing == null) return true;
      if (existing != command) return false;
      return await _preferences.remove(_key(accountId));
    } catch (_) {
      return false;
    }
  }
}

final class MemoryInvitationCreateMutationStore
    implements InvitationCreateMutationStore {
  final _commands = <String, InvitationCreateCommand>{};

  @override
  Future<InvitationCreateCommand?> read(String accountId) async =>
      _commands[accountId];

  @override
  Future<bool> write(String accountId, InvitationCreateCommand command) async {
    final existing = _commands[accountId];
    if (existing != null && existing != command) return false;
    _commands[accountId] = command;
    return true;
  }

  @override
  Future<bool> remove(String accountId, InvitationCreateCommand command) async {
    final existing = _commands[accountId];
    if (existing == null) return true;
    if (existing != command) return false;
    _commands.remove(accountId);
    return true;
  }
}
