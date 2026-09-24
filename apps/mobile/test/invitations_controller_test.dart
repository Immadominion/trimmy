import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/practice_sync/http_transport.dart';
import 'package:trimmy/social/http_invitations_client.dart';
import 'package:trimmy/social/invitation.dart';
import 'package:trimmy/social/invitation_create_store.dart';
import 'package:trimmy/social/invitations_controller.dart';

const _account = '9f000000-0000-4000-8000-000000000001';
const _id = '11111111-1111-4111-8111-111111111111';
const _second = '22222222-2222-4222-8222-222222222222';
const _mutation = '33333333-3333-4333-8333-333333333333';
const _social = '44444444-4444-4444-8444-444444444444';
final _base = Uri.parse('https://api.example');

const _senderJson = {
  'socialId': _social,
  'handle': 'mira_trade',
  'persona': 'oracle',
  'rank': {'id': 'rookie', 'label': 'Rookie'},
};
const _recipientJson = {'provider': 'x', 'handleSnapshot': 'ada_builds'};

Map<String, Object?> _row({
  String state = 'draft',
  String role = 'sender',
  Object? recipient,
  int version = 0,
  String id = _id,
  String createdAt = '2026-09-16T10:00:00.000Z',
  String? acceptedAt,
}) => <String, Object?>{
  'schemaVersion': 2,
  'id': id,
  'state': state,
  'funding': 'unfunded',
  'sender': _senderJson,
  'recipient': recipient,
  'expiresAt': '2030-01-01T12:00:00.000Z',
  'createdAt': createdAt,
  'acceptedAt': acceptedAt,
  'version': version,
  'role': role,
};

Map<String, Object?> _page(
  List<Object?> rows, {
  String incoming = 'available',
  String? nextCursor,
}) => {
  'schemaVersion': 2,
  'incomingInvitations': incoming,
  'invitations': rows,
  'nextCursor': nextCursor,
};

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

({InvitationsController controller, List<http.BaseRequest> calls}) _build({
  required Future<http.Response> Function(http.BaseRequest request) route,
  InvitationCreateMutationStore? createMutationStore,
  InvitationMutationIdFactory? mutationId,
  InvitationClock? clock,
}) {
  final calls = <http.BaseRequest>[];
  final transport = MockClient((request) {
    calls.add(request);
    return route(request);
  });
  final controller = InvitationsController(
    client: HttpInvitationsClient(
      client: transport,
      baseUri: _base,
      accountId: _account,
      accessToken: () async =>
          const PracticeAccessToken(accountId: _account, token: 'a.b.c'),
    ),
    mutationId: mutationId ?? () => _mutation,
    createMutationStore: createMutationStore,
    clock: clock ?? () => DateTime.parse('2029-12-25T12:00:00.000Z'),
  );
  addTearDown(() {
    controller.dispose();
    transport.close();
  });
  return (controller: controller, calls: calls);
}

void main() {
  test('open read separates roles and exposes X-link availability', () async {
    final built = _build(
      route: (_) async => _json(
        _page([
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

    await built.controller.refresh();

    expect(built.controller.loaded, isTrue);
    expect(built.controller.sent, hasLength(1));
    expect(built.controller.received, hasLength(1));
    expect(
      built.controller.incomingInvitations,
      IncomingInvitationsStatus.available,
    );
    expect(built.calls.single.url.queryParameters, {
      'box': 'open',
      'limit': '$invitationPageLimit',
    });
  });

  test('losing the X link clears cached open invitations received', () async {
    var history = false;
    final built = _build(
      route: (request) async {
        history = request.url.queryParameters['box'] == 'history';
        if (history) {
          return _json(
            _page([_row(state: 'canceled')], incoming: 'x_link_required'),
          );
        }
        return _json(
          _page([
            _row(
              role: 'recipient',
              state: 'offered',
              recipient: _recipientJson,
              version: 2,
            ),
          ]),
        );
      },
    );
    await built.controller.refresh();
    expect(built.controller.received, hasLength(1));

    await built.controller.refreshHistory();

    expect(history, isTrue);
    expect(built.controller.received, isEmpty);
    expect(
      built.controller.incomingInvitations,
      IncomingInvitationsStatus.xLinkRequired,
    );
  });

  test(
    'create uses one generated mutation and adds its draft locally',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final built = _build(
        route: (request) async {
          if (request.method == 'POST') {
            bodies.add(jsonDecode((request as http.Request).body));
            return _json(_row());
          }
          return _json(_page(const []));
        },
      );
      await built.controller.refresh();
      await built.controller.create();
      expect(built.controller.invitations.single.state, InvitationState.draft);
      expect(bodies.single['schemaVersion'], 2);
      expect(bodies.single['mutationId'], _mutation);
      expect(bodies.single.keys, {'schemaVersion', 'mutationId', 'expiresAt'});
    },
  );

  test(
    'create replays its exact persisted command after an ambiguous restart',
    () async {
      final store = MemoryInvitationCreateMutationStore();
      final bodies = <Map<String, dynamic>>[];
      var generated = 0;
      final first = _build(
        createMutationStore: store,
        clock: () => DateTime.parse('2029-12-25T12:00:00.000Z'),
        mutationId: () {
          generated++;
          return _mutation;
        },
        route: (request) async {
          bodies.add(jsonDecode((request as http.Request).body));
          // The request may already have committed when the connection drops.
          throw http.ClientException('response lost');
        },
      );

      await first.controller.create();
      expect(first.controller.failure, InvitationFailure.unavailable);
      expect(generated, 1);
      first.controller.dispose();

      final second = _build(
        createMutationStore: store,
        // A local clock jump must not discard a possibly committed command.
        clock: () => DateTime.parse('2031-01-01T12:00:00.000Z'),
        mutationId: () {
          generated++;
          return _second;
        },
        route: (request) async {
          bodies.add(jsonDecode((request as http.Request).body));
          return _json(_row());
        },
      );
      await second.controller.resumePendingCreate();

      expect(generated, 1);
      expect(bodies, hasLength(2));
      expect(bodies[1], bodies[0]);
      expect(second.controller.failure, isNull);
      expect(second.controller.invitations.single.id, _id);
      expect(await store.read(_account), isNull);
    },
  );

  test('create replay clears a command closed by another device', () async {
    final store = MemoryInvitationCreateMutationStore();
    final first = _build(
      createMutationStore: store,
      clock: () => DateTime.parse('2029-12-25T12:00:00.000Z'),
      route: (_) async => throw http.ClientException('response lost'),
    );
    await first.controller.create();
    expect(await store.read(_account), isNotNull);
    first.controller.dispose();

    final second = _build(
      createMutationStore: store,
      route: (_) async => _json(_row(state: 'canceled', version: 2)),
    );
    await second.controller.resumePendingCreate();

    expect(second.controller.failure, isNull);
    expect(second.controller.openInvitations, isEmpty);
    expect(
      second.controller.historyInvitations.single.state,
      InvitationState.canceled,
    );
    expect(await store.read(_account), isNull);
  });

  test('addressing sends the typed handle straight to the server', () async {
    final paths = <String>[];
    Map<String, dynamic>? actionBody;
    final built = _build(
      route: (request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/actions')) {
          actionBody = jsonDecode((request as http.Request).body);
          return _json(
            _row(state: 'addressed', recipient: _recipientJson, version: 1),
          );
        }
        if (request.method == 'POST') return _json(_row());
        return _json(_page(const []));
      },
    );

    await built.controller.create();
    await built.controller.addressByHandle(
      built.controller.invitations.single,
      ' @Ada_Builds ',
    );

    expect(actionBody, {
      'schemaVersion': 2,
      'action': 'address',
      'expectedVersion': 0,
      'xHandle': 'Ada_Builds',
    });
    expect(actionBody.toString(), isNot(contains('subject')));
    expect(paths.where((path) => path.startsWith('/v1/social/x')), isEmpty);
    expect(
      built.controller.invitations.single.recipient?.handleSnapshot,
      'ada_builds',
    );
  });

  test('open and history pages append with their own opaque cursors', () async {
    var openReads = 0;
    var historyReads = 0;
    final built = _build(
      route: (request) async {
        final history = request.url.queryParameters['box'] == 'history';
        final cursor = request.url.queryParameters['cursor'];
        if (history) {
          historyReads++;
          return _json(
            _page([
              _row(
                id: cursor == null ? _id : _second,
                state: 'canceled',
                createdAt: cursor == null
                    ? '2026-09-16T10:00:00.000Z'
                    : '2026-09-16T09:00:00.000Z',
              ),
            ], nextCursor: cursor == null ? 'history_cursor' : null),
          );
        }
        openReads++;
        return _json(
          _page([
            _row(
              id: cursor == null ? _id : _second,
              createdAt: cursor == null
                  ? '2026-09-16T10:00:00.000Z'
                  : '2026-09-16T09:00:00.000Z',
            ),
          ], nextCursor: cursor == null ? 'open_cursor' : null),
        );
      },
    );

    await built.controller.refresh();
    await built.controller.loadMoreOpen();
    await built.controller.refreshHistory();
    await built.controller.loadMoreHistory();

    expect(openReads, 2);
    expect(historyReads, 2);
    expect(built.controller.openInvitations.map((row) => row.id), [
      _id,
      _second,
    ]);
    expect(built.controller.historyInvitations.map((row) => row.id), [
      _id,
      _second,
    ]);
    expect(built.controller.hasMoreOpen, isFalse);
    expect(built.controller.hasMoreHistory, isFalse);
  });

  test(
    'a repeated or overlapping page is rejected without replacing rows',
    () async {
      var reads = 0;
      final built = _build(
        route: (_) async {
          reads++;
          return _json(
            _page([
              _row(),
            ], nextCursor: reads == 1 ? 'same_cursor' : 'same_cursor'),
          );
        },
      );
      await built.controller.refresh();
      await built.controller.loadMoreOpen();
      expect(built.controller.failure, InvitationFailure.invalidResponse);
      expect(built.controller.invitations.map((row) => row.id), [_id]);
    },
  );

  test('a stale action refreshes the open page before reporting', () async {
    var reads = 0;
    final built = _build(
      route: (request) async {
        if (request.method == 'POST') {
          return _json({
            'error': {
              'code': 'INVITATION_VERSION_CONFLICT',
              'message': 'The invitation changed.',
              'requestId': 'request-one',
            },
          }, 409);
        }
        reads++;
        return _json(
          _page([
            _row(
              state: reads == 1 ? 'addressed' : 'offered',
              recipient: _recipientJson,
              version: reads == 1 ? 1 : 2,
            ),
          ]),
        );
      },
    );
    await built.controller.refresh();
    await built.controller.act(
      built.controller.invitations.single,
      InvitationAction.offer,
    );
    expect(built.controller.failure, InvitationFailure.versionConflict);
    expect(built.controller.invitations.single.state, InvitationState.offered);
    expect(built.controller.invitations.single.version, 2);
  });

  test(
    'one operation runs at a time and disposal clears account state',
    () async {
      final held = Completer<http.Response>();
      final built = _build(route: (_) => held.future);
      final first = built.controller.refresh();
      await built.controller.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(built.calls, hasLength(1));
      built.controller.dispose();
      expect(built.controller.invitations, isEmpty);
      expect(built.controller.historyInvitations, isEmpty);
      expect(built.controller.incomingInvitations, isNull);
      held.complete(_json(_page([_row()])));
      await first;
      expect(built.controller.invitations, isEmpty);
    },
  );
}
