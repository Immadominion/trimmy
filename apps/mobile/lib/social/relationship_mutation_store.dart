import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'relationship.dart';

const _maximumPendingRelationshipMutations = 32;

abstract interface class RelationshipMutationStore {
  Future<List<RelationshipMutationCommand>> read(String accountId);
  Future<bool> write(String accountId, RelationshipMutationCommand command);
  Future<bool> remove(String accountId, RelationshipMutationCommand command);
}

/// Account-scoped command journal for writes whose response may be lost.
///
/// It stores public UUIDs, revisions and fixed report categories only. Bearers,
/// provider identities, private reason text and account profile data are never
/// written here.
final class PreferencesRelationshipMutationStore
    implements RelationshipMutationStore {
  const PreferencesRelationshipMutationStore(this._preferences);

  static const _prefix = 'trimmy.social.pending-relationship-mutations.v1.';
  final SharedPreferences _preferences;

  String _key(String accountId) => '$_prefix$accountId';

  @override
  Future<List<RelationshipMutationCommand>> read(String accountId) async {
    try {
      await _preferences.reload();
      final encoded = _preferences.getString(_key(accountId));
      if (encoded == null) return const [];
      final value = jsonDecode(encoded);
      if (value is! Map<String, dynamic> ||
          value.length != 2 ||
          value['schemaVersion'] != 1 ||
          value['commands'] is! List) {
        throw const RelationshipException(RelationshipFailure.invalidResponse);
      }
      final raw = value['commands'] as List;
      if (raw.length > _maximumPendingRelationshipMutations) {
        throw const RelationshipException(RelationshipFailure.invalidResponse);
      }
      final commands = raw
          .map(RelationshipMutationCommand.fromStoredJson)
          .toList(growable: false);
      final mutationIds = <String>{};
      if (commands.any((command) => !mutationIds.add(command.mutationId))) {
        throw const RelationshipException(RelationshipFailure.invalidResponse);
      }
      return List.unmodifiable(commands);
    } on RelationshipException {
      rethrow;
    } catch (_) {
      throw const RelationshipException(RelationshipFailure.unavailable);
    }
  }

  @override
  Future<bool> write(
    String accountId,
    RelationshipMutationCommand command,
  ) async {
    try {
      final commands = await read(accountId);
      final existing = commands
          .where((item) => item.mutationId == command.mutationId)
          .firstOrNull;
      if (existing != null) return existing == command;
      if (commands.length >= _maximumPendingRelationshipMutations) return false;
      return _save(accountId, [...commands, command]);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> remove(
    String accountId,
    RelationshipMutationCommand command,
  ) async {
    try {
      final commands = await read(accountId);
      final existing = commands
          .where((item) => item.mutationId == command.mutationId)
          .firstOrNull;
      if (existing == null) return true;
      if (existing != command) return false;
      return _save(accountId, [
        for (final item in commands)
          if (item.mutationId != command.mutationId) item,
      ]);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _save(
    String accountId,
    List<RelationshipMutationCommand> commands,
  ) async {
    if (commands.isEmpty) return _preferences.remove(_key(accountId));
    final encoded = jsonEncode({
      'schemaVersion': 1,
      'commands': commands.map((command) => command.toStoredJson()).toList(),
    });
    if (encoded.length > 16384) return false;
    return _preferences.setString(_key(accountId), encoded);
  }
}

final class MemoryRelationshipMutationStore
    implements RelationshipMutationStore {
  final _commands = <String, List<RelationshipMutationCommand>>{};

  @override
  Future<List<RelationshipMutationCommand>> read(String accountId) async =>
      List.unmodifiable(_commands[accountId] ?? const []);

  @override
  Future<bool> write(
    String accountId,
    RelationshipMutationCommand command,
  ) async {
    final commands = _commands[accountId] ?? const [];
    final existing = commands
        .where((item) => item.mutationId == command.mutationId)
        .firstOrNull;
    if (existing != null) return existing == command;
    if (commands.length >= _maximumPendingRelationshipMutations) return false;
    _commands[accountId] = List.unmodifiable([...commands, command]);
    return true;
  }

  @override
  Future<bool> remove(
    String accountId,
    RelationshipMutationCommand command,
  ) async {
    final commands = _commands[accountId] ?? const [];
    final existing = commands
        .where((item) => item.mutationId == command.mutationId)
        .firstOrNull;
    if (existing == null) return true;
    if (existing != command) return false;
    final next = [
      for (final item in commands)
        if (item.mutationId != command.mutationId) item,
    ];
    if (next.isEmpty) {
      _commands.remove(accountId);
    } else {
      _commands[accountId] = List.unmodifiable(next);
    }
    return true;
  }
}
