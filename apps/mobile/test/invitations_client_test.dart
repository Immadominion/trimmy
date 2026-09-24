import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/practice_sync/http_transport.dart';
import 'package:trimmy/social/http_invitations_client.dart';
import 'package:trimmy/social/invitation.dart';

const _account = '9f000000-0000-4000-8000-000000000001';
const _other = '9f000000-0000-4000-8000-000000000002';
const _id = '11111111-1111-4111-8111-111111111111';
const _second = '22222222-2222-4222-8222-222222222222';
const _mutation = '33333333-3333-4333-8333-333333333333';
const _social = '44444444-4444-4444-8444-444444444444';
final _base = Uri.parse('https://api.example');
final _expires = DateTime.utc(2030, 1, 1, 12);

class _Sent {
  _Sent(this.method, this.url, this.body);
  final String method;
  final Uri url;
  final String body;
}

const _senderJson = {
  'socialId': _social,
  'handle': 'mira_trade',
  'persona': 'oracle',
  'rank': {'id': 'rookie', 'label': 'Rookie'},
};

const _recipientJson = {'provider': 'x', 'handleSnapshot': 'ada_builds'};

Map<String, Object?> _row({
  String id = _id,
  String state = 'draft',
  String role = 'sender',
  Object? sender = _senderJson,
  Object? recipient,
  String? acceptedAt,
  int version = 0,
  String funding = 'unfunded',
  String createdAt = '2026-09-16T10:00:00.000Z',
  String expiresAt = '2030-01-01T12:00:00.000Z',
}) => <String, Object?>{
  'schemaVersion': 2,
  'id': id,
  'state': state,
  'funding': funding,
  'sender': sender,
  'recipient': recipient,
  'expiresAt': expiresAt,
  'createdAt': createdAt,
  'acceptedAt': acceptedAt,
  'version': version,
  'role': role,
};

Map<String, Object?> _page(
  List<Object?> invitations, {
  String incoming = 'available',
  String? nextCursor,
}) => {
  'schemaVersion': 2,
  'incomingInvitations': incoming,
  'invitations': invitations,
  'nextCursor': nextCursor,
};

http.Client _stub({
  int status = 200,
  Object? json,
  String? rawBody,
  String contentType = 'application/json',
  List<_Sent>? sent,
  Exception? throws,
}) => MockClient((request) async {
  sent?.add(_Sent(request.method, request.url, request.body));
  if (throws != null) throw throws;
  return http.Response(
    rawBody ?? jsonEncode(json ?? const {}),
    status,
    headers: {'content-type': contentType},
  );
});

HttpInvitationsClient _client(
  http.Client transport, {
  String tokenAccount = _account,
  String token = 'header.payload.signature',
  Object? tokenError,
}) => HttpInvitationsClient(
  client: transport,
  baseUri: _base,
  accountId: _account,
  accessToken: () async {
    if (tokenError != null) throw tokenError;
    return PracticeAccessToken(accountId: tokenAccount, token: token);
  },
);

Future<InvitationFailure> _failed(Future<Object?> work) async {
  try {
    await work;
  } on InvitationException catch (error) {
    return error.failure;
  }
  throw StateError('expected an InvitationException but the call succeeded');
}

void main() {
  test(
    'open list is bounded and reads the exact v2 public projection',
    () async {
      final sent = <_Sent>[];
      final client = _client(
        _stub(
          sent: sent,
          json: _page([
            _row(state: 'offered', recipient: _recipientJson, version: 2),
            _row(
              id: _second,
              role: 'recipient',
              state: 'offered',
              recipient: _recipientJson,
              version: 2,
              createdAt: '2026-09-16T09:00:00.000Z',
            ),
          ]),
        ),
      );

      final page = await client.list(limit: 20);

      expect(sent.single.method, 'GET');
      expect(sent.single.url.path, '/v1/invitations');
      expect(sent.single.url.queryParameters, {'box': 'open', 'limit': '20'});
      expect(page.box, InvitationBox.open);
      expect(page.incomingInvitations, IncomingInvitationsStatus.available);
      expect(page.invitations.map((row) => row.id), [_id, _second]);
      expect(page.invitations.first.sender.handle, 'mira_trade');
      expect(page.invitations.first.sender.rank.label, 'Rookie');
      expect(page.invitations.first.recipient?.handleSnapshot, 'ada_builds');
      expect(page.invitations.last.availableActions, {
        InvitationAction.accept,
        InvitationAction.decline,
      });
    },
  );

  test(
    'history pagination round-trips its cursor as an opaque string',
    () async {
      final sent = <_Sent>[];
      const cursor = 'eyJraW5kIjoiaW52aXRhdGlvbnMifQ';
      final client = _client(
        _stub(
          sent: sent,
          json: _page([
            _row(
              state: 'accepted',
              role: 'recipient',
              recipient: _recipientJson,
              acceptedAt: '2026-09-16T11:00:00.000Z',
              version: 3,
            ),
          ], incoming: 'x_link_required'),
        ),
      );

      final page = await client.list(
        box: InvitationBox.history,
        limit: 7,
        cursor: cursor,
      );

      expect(sent.single.url.queryParameters, {
        'box': 'history',
        'limit': '7',
        'cursor': cursor,
      });
      expect(page.incomingInvitations, IncomingInvitationsStatus.xLinkRequired);
      expect(page.invitations.single.acceptedAt, DateTime.utc(2026, 9, 16, 11));
    },
  );

  test('create sends schema v2 mutation and millisecond expiry', () async {
    final sent = <_Sent>[];
    final client = _client(
      MockClient((request) async {
        sent.add(_Sent(request.method, request.url, request.body));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode(_row(expiresAt: body['expiresAt'] as String)),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    final created = await client.create(
      mutationId: _mutation,
      expiresAt: _expires,
    );
    expect(created.state, InvitationState.draft);
    expect(jsonDecode(sent.single.body), {
      'schemaVersion': 2,
      'mutationId': _mutation,
      'expiresAt': '2030-01-01T12:00:00.000Z',
    });
    expect(
      await _failed(
        client.create(mutationId: 'not-a-uuid', expiresAt: _expires),
      ),
      InvitationFailure.invalidRequest,
    );
    expect(sent, hasLength(1));

    final replay = await client.create(
      mutationId: _mutation,
      expiresAt: DateTime.parse('2020-01-01T12:00:00.000Z'),
    );
    expect(replay.state, InvitationState.draft);
    expect(jsonDecode(sent.last.body)['expiresAt'], '2020-01-01T12:00:00.000Z');
  });

  test('create replay accepts the sender invitation current state', () async {
    for (final row in [
      _row(state: 'addressed', recipient: _recipientJson, version: 1),
      _row(state: 'canceled', version: 2),
    ]) {
      final client = _client(_stub(json: row));
      final replay = await client.create(
        mutationId: _mutation,
        expiresAt: _expires,
      );
      expect(replay.isSender, isTrue);
      expect(replay.state, isNot(InvitationState.draft));
    }
  });

  test(
    'address sends only xHandle and other actions send no identity',
    () async {
      final sent = <_Sent>[];
      for (final action in InvitationAction.values) {
        final client = _client(
          _stub(
            json: _row(
              state: 'addressed',
              recipient: _recipientJson,
              version: 1,
            ),
            sent: sent,
          ),
        );
        await client.act(
          invitationId: _id,
          action: action,
          expectedVersion: 1,
          xHandle: action == InvitationAction.address ? 'Ada_Builds' : null,
        );
      }
      expect(jsonDecode(sent.first.body), {
        'schemaVersion': 2,
        'action': 'address',
        'expectedVersion': 1,
        'xHandle': 'Ada_Builds',
      });
      for (final call in sent.skip(1)) {
        expect(jsonDecode(call.body), {
          'schemaVersion': 2,
          'action': (jsonDecode(call.body) as Map)['action'],
          'expectedVersion': 1,
        });
        expect(call.body, isNot(contains('subject')));
        expect(call.body, isNot(contains('xHandle')));
      }
    },
  );

  test('invalid action identity and list controls never send', () async {
    final sent = <_Sent>[];
    final client = _client(_stub(sent: sent));
    expect(
      await _failed(
        client.act(
          invitationId: _id,
          action: InvitationAction.address,
          expectedVersion: 0,
        ),
      ),
      InvitationFailure.invalidRequest,
    );
    expect(
      await _failed(
        client.act(
          invitationId: _id,
          action: InvitationAction.offer,
          expectedVersion: 1,
          xHandle: 'ada_builds',
        ),
      ),
      InvitationFailure.invalidRequest,
    );
    expect(
      await _failed(client.list(limit: 51)),
      InvitationFailure.invalidRequest,
    );
    expect(
      await _failed(client.list(cursor: 'not a cursor')),
      InvitationFailure.invalidRequest,
    );
    expect(sent, isEmpty);
  });

  test('v1 and any response containing an X subject are refused', () async {
    final subjectRecipient = {..._recipientJson, 'subject': '1499'};
    final badRows = <Object?>[
      {..._row(), 'schemaVersion': 1},
      _row(state: 'offered', recipient: subjectRecipient),
      _row(sender: {..._senderJson, 'extra': true}),
      _row(sender: {..._senderJson, 'persona': 'spark'}),
      _row(
        sender: {
          ..._senderJson,
          'rank': {'id': 'rookie', 'label': 'Intern'},
        },
      ),
      _row(createdAt: '2026-09-16T10:00:00Z'),
    ];
    for (final row in badRows) {
      final client = _client(_stub(json: row));
      expect(
        await _failed(
          client.create(mutationId: _mutation, expiresAt: _expires),
        ),
        InvitationFailure.invalidResponse,
        reason: jsonEncode(row),
      );
    }
  });

  test('box membership, page order and envelope shape are enforced', () async {
    final cases = <Object?>[
      _page([_row(state: 'canceled')]),
      _page([_row()]),
      _page([
        _row(createdAt: '2026-09-16T09:00:00.000Z'),
        _row(id: _second, createdAt: '2026-09-16T10:00:00.000Z'),
      ]),
      {..._page(const []), 'total': 0},
      _page(const [], nextCursor: 'not a cursor'),
    ];
    expect(
      await _failed(_client(_stub(json: cases[0])).list()),
      InvitationFailure.invalidResponse,
    );
    expect(
      await _failed(
        _client(_stub(json: cases[1])).list(box: InvitationBox.history),
      ),
      InvitationFailure.invalidResponse,
    );
    for (final value in cases.skip(2)) {
      expect(
        await _failed(_client(_stub(json: value)).list()),
        InvitationFailure.invalidResponse,
      );
    }
  });

  test('stable social and invitation errors map to useful failures', () async {
    final cases = <String, InvitationFailure>{
      'INVITATION_VERSION_CONFLICT': InvitationFailure.versionConflict,
      'SOCIAL_INVITATION_IDEMPOTENCY_CONFLICT':
          InvitationFailure.idempotencyConflict,
      'SOCIAL_IDENTITY_UNAVAILABLE': InvitationFailure.xLinkRequired,
      'SOCIAL_IDENTITY_CONFLICT': InvitationFailure.identityConflict,
      'SOCIAL_PAIR_UNAVAILABLE': InvitationFailure.relationshipUnavailable,
      'SOCIAL_RATE_LIMITED': InvitationFailure.rateLimited,
      'X_PROFILE_NOT_FOUND': InvitationFailure.xHandleNotFound,
    };
    for (final entry in cases.entries) {
      final client = _client(
        _stub(
          status: entry.value == InvitationFailure.rateLimited ? 429 : 409,
          json: {
            'error': {
              'code': entry.key,
              'message': 'Safe public message.',
              'requestId': 'request-one',
            },
          },
        ),
      );
      expect(await _failed(client.list()), entry.value, reason: entry.key);
    }
  });

  test('malformed or widened invitation errors fail closed', () async {
    for (final response in [
      _stub(
        status: 429,
        json: {
          'error': {
            'code': 'SOCIAL_RATE_LIMITED',
            'message': 'Safe public message.',
            'requestId': 'request-one',
            'providerPayload': 'private',
          },
        },
      ),
      _stub(
        status: 503,
        rawBody: '<html>gateway</html>',
        contentType: 'text/html',
      ),
    ]) {
      expect(
        await _failed(_client(response).list()),
        InvitationFailure.invalidResponse,
      );
    }
  });

  test('account binding, closure and configuration stay strict', () async {
    final sent = <_Sent>[];
    expect(
      await _failed(_client(_stub(sent: sent), tokenAccount: _other).list()),
      InvitationFailure.accountMismatch,
    );
    expect(sent, isEmpty);
    final client = _client(_stub(json: _page(const [])));
    final first = client.list();
    expect(await _failed(client.list()), InvitationFailure.busy);
    expect((await first).invitations, isEmpty);
    client.close();
    expect(await _failed(client.list()), InvitationFailure.closed);
    expect(
      () => HttpInvitationsClient(
        client: _stub(),
        baseUri: Uri.parse('http://api.example'),
        accountId: _account,
        accessToken: () async =>
            PracticeAccessToken(accountId: _account, token: 'a.b.c'),
      ),
      throwsA(isA<InvitationException>()),
    );
  });

  test('available actions follow state and role', () {
    InvitationRecord record(String state, String role) =>
        InvitationRecord.fromJson(
          _row(
            state: state,
            role: role,
            recipient: state == 'draft' ? null : _recipientJson,
            acceptedAt: state == 'accepted' ? '2026-09-16T11:00:00.000Z' : null,
          ),
        );
    expect(record('draft', 'sender').availableActions, {
      InvitationAction.address,
      InvitationAction.cancel,
    });
    expect(record('offered', 'sender').availableActions, {
      InvitationAction.cancel,
    });
    expect(record('offered', 'recipient').availableActions, {
      InvitationAction.accept,
      InvitationAction.decline,
    });
    for (final state in ['accepted', 'declined', 'expired', 'canceled']) {
      expect(record(state, 'sender').availableActions, isEmpty);
    }
  });
}
