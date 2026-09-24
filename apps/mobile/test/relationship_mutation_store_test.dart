import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/social/relationship.dart';
import 'package:trimmy/social/relationship_mutation_store.dart';

const _account = '90000000-0000-4000-8000-000000000001';
const _otherAccount = '90000000-0000-4000-8000-000000000002';
const _friendship = '10000000-0000-4000-8000-000000000001';
const _social = '20000000-0000-4000-8000-000000000001';
const _mutation = '30000000-0000-4000-8000-000000000001';
const _reason = '40000000-0000-4000-8000-000000000001';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('preferences preserve exact public commands by account', () async {
    final preferences = await SharedPreferences.getInstance();
    var store = PreferencesRelationshipMutationStore(preferences);
    final remove = FriendRemoveCommand(
      friendshipId: _friendship,
      mutationId: _mutation,
      expectedRevision: 4,
    );

    expect(await store.write(_account, remove), isTrue);
    store = PreferencesRelationshipMutationStore(preferences);

    expect(await store.read(_account), [remove]);
    expect(await store.read(_otherAccount), isEmpty);
    expect(await store.write(_account, remove), isTrue);
    expect(
      await store.write(
        _account,
        FriendRemoveCommand(
          friendshipId: _friendship,
          mutationId: _mutation,
          expectedRevision: 5,
        ),
      ),
      isFalse,
    );
    expect(await store.remove(_account, remove), isTrue);
    expect(await store.read(_account), isEmpty);
  });

  test('all safety command kinds round-trip without private content', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = PreferencesRelationshipMutationStore(preferences);
    final commands = <RelationshipMutationCommand>[
      BlockCommand(
        socialId: _social,
        mutationId: _mutation,
        baseRevision: 2,
        blocked: false,
      ),
      ReasonReportCommand(
        mutationId: '30000000-0000-4000-8000-000000000002',
        reasonId: _reason,
        category: ReasonReportCategory.unsafe,
      ),
    ];

    for (final command in commands) {
      expect(await store.write(_account, command), isTrue);
    }

    expect(await store.read(_account), commands);
    final stored = preferences.getKeys().single;
    final encoded = preferences.getString(stored)!;
    expect(encoded, isNot(contains('Bearer')));
    expect(encoded, isNot(contains('note')));
    expect(encoded, isNot(contains('subject')));
  });

  test('corrupt or extended stored commands fail closed', () async {
    for (final encoded in [
      '{"schemaVersion":1,"commands":"wrong"}',
      '{"schemaVersion":1,"commands":[{"schemaVersion":1,"kind":"put-block","socialId":"$_social","mutationId":"$_mutation","baseRevision":0,"blocked":true,"xSubject":"42"}]}',
    ]) {
      SharedPreferences.setMockInitialValues({
        'trimmy.social.pending-relationship-mutations.v1.$_account': encoded,
      });
      final preferences = await SharedPreferences.getInstance();
      final store = PreferencesRelationshipMutationStore(preferences);
      await expectLater(
        store.read(_account),
        throwsA(isA<RelationshipException>()),
      );
    }
  });
}
