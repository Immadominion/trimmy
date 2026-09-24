import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/social/invitation.dart';
import 'package:trimmy/social/invitation_create_store.dart';

const _account = '9f000000-0000-4000-8000-000000000001';
const _mutation = '33333333-3333-4333-8333-333333333333';
const _otherMutation = '44444444-4444-4444-8444-444444444444';
final _expiry = DateTime.parse('2030-01-01T12:00:00.000Z');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('create command requires exact public replay fields', () {
    final command = InvitationCreateCommand(
      mutationId: _mutation,
      expiresAt: _expiry,
    );
    expect(InvitationCreateCommand.fromJson(command.toJson()), command);
    expect(
      () => InvitationCreateCommand.fromJson({
        ...command.toJson(),
        'xSubject': '12345',
      }),
      throwsA(
        isA<InvitationException>().having(
          (error) => error.failure,
          'failure',
          InvitationFailure.invalidResponse,
        ),
      ),
    );
  });

  test('preferences keep the exact command across store instances', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final first = PreferencesInvitationCreateMutationStore(preferences);
    final command = InvitationCreateCommand(
      mutationId: _mutation,
      expiresAt: _expiry,
    );
    expect(await first.write(_account, command), isTrue);

    final restored = PreferencesInvitationCreateMutationStore(preferences);
    expect(await restored.read(_account), command);
    expect(
      await restored.write(
        _account,
        InvitationCreateCommand(mutationId: _otherMutation, expiresAt: _expiry),
      ),
      isFalse,
    );
    expect(await restored.read(_account), command);
    expect(await restored.remove(_account, command), isTrue);
    expect(await restored.read(_account), isNull);
  });
}
