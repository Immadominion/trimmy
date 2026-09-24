import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/practice_sync/http_transport.dart';
import 'package:trimmy/product/market/market.dart';
import 'package:trimmy/social/http_relationships_client.dart';
import 'package:trimmy/social/relationships_controller.dart';

import '../career/reason_sharing_test_support.dart';
import 'market_test_support.dart';

const _reasonA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _reasonB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _reasonC = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _orderA = '44444444-4444-4444-8444-444444444444';
const _socialA = '55555555-5555-4555-8555-555555555555';
const _socialB = '66666666-6666-4666-8666-666666666666';
const _account = '77777777-7777-4777-8777-777777777777';
const _report = '88888888-8888-4888-8888-888888888888';

void main() {
  testWidgets('without a repository the tab says reasons are unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(_app(repository: null));

    expect(find.text('No comments yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('stock-reasons-footer')), findsNothing);
  });

  testWidgets('shows a skeleton, then rows with handle, rank, note and time', (
    tester,
  ) async {
    final gate = Completer<ReasonPage<SharedReason>>();
    final repository = FakeReasonSharingRepository()
      ..onShared = (_) => gate.future;
    await tester.pumpWidget(_app(repository: repository));

    expect(find.byKey(const ValueKey('stock-reasons-loading')), findsOneWidget);
    expect(find.bySemanticsLabel('Loading comments'), findsOneWidget);
    expect(repository.sharedQueries.single.assetId, 'apple');
    expect(repository.sharedQueries.single.variantMint, testMint);
    expect(repository.sharedQueries.single.cursor, isNull);

    gate.complete(
      ReasonPage(
        items: [
          testSharedReason(
            reasonId: _reasonA,
            handle: 'mira',
            rank: CareerRank.rookie,
            isViewer: true,
            note: 'Bought after the product event.',
          ),
          testSharedReason(reasonId: _reasonB),
        ],
        limit: 20,
        nextCursor: null,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('stock-reasons-loading')), findsNothing);
    expect(find.text('@mira'), findsOneWidget);
    expect(find.text('Rookie'), findsOneWidget);
    expect(find.text('Bought after the product event.'), findsOneWidget);
    expect(find.text('@ada_trade'), findsOneWidget);
    expect(find.text('Analyst'), findsOneWidget);
    expect(find.textContaining('Saved 20 Sep 2026'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('stock-reason-you-$_reasonA')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('stock-reason-you-$_reasonB')),
      findsNothing,
    );
    expect(find.text('You'), findsOneWidget);
    expect(find.byKey(const ValueKey('stock-reasons-more')), findsNothing);
    expect(
      find.text('Only people who chose Everyone show here.'),
      findsNothing,
    );
    expect(find.textContaining('Entry'), findsNothing);
  });

  testWidgets('an empty page shows the honest empty line and footer', (
    tester,
  ) async {
    final repository = FakeReasonSharingRepository()
      ..onShared = (query) =>
          ReasonPage(items: const [], limit: query.limit, nextCursor: null);
    await tester.pumpWidget(_app(repository: repository));
    await tester.pumpAndSettle();

    expect(find.text('No comments yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('stock-reasons-footer')), findsNothing);
  });

  testWidgets('available friends scope replaces the exact-stock page', (
    tester,
  ) async {
    final repository = FakeReasonSharingRepository()
      ..onShared = (query) {
        return ReasonPage(
          items: [testSharedReason(reasonId: _reasonA, handle: 'the_market')],
          limit: query.limit,
          nextCursor: null,
        );
      }
      ..onFriends = (query) {
        return ReasonPage(
          items: [
            testSharedReason(
              reasonId: _reasonB,
              handle: 'market_friend',
              note: 'The balance sheet finally turned the corner.',
            ),
          ],
          limit: query.limit,
          nextCursor: null,
        );
      }
      ..privacyReads.add(
        testPrivacy(
          revision: 2,
          visibility: ReasonVisibility.friends,
          friendsSharing: FriendsSharingAvailability.available,
        ),
      );
    final privacy = ReasonPrivacyController(
      mutationId: () => testReasonMutation,
    );
    addTearDown(privacy.dispose);
    await privacy.bind(principalKey: 'account:one', repository: repository);

    await tester.pumpWidget(
      _app(repository: repository, viewerPrivacy: privacy),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('stock-reasons-audience-everyone')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('stock-reasons-audience-friends')),
      findsOneWidget,
    );
    expect(find.text('@the_market'), findsOneWidget);
    expect(find.text('@market_friend'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('stock-reasons-audience-friends')),
    );
    await tester.pumpAndSettle();

    expect(repository.friendQueries, hasLength(1));
    expect(repository.friendQueries.single.assetId, 'apple');
    expect(repository.friendQueries.single.variantMint, testMint);
    expect(find.text('@the_market'), findsNothing);
    expect(find.text('@market_friend'), findsOneWidget);
    expect(
      find.text('The balance sheet finally turned the corner.'),
      findsOneWidget,
    );
    expect(
      find.text('Friends who chose Friends or Everyone show here.'),
      findsNothing,
    );
  });

  testWidgets(
    'report chooses a fixed category, confirms, and hides only after success',
    (tester) async {
      final gate = Completer<http.Response>();
      Map<String, dynamic>? sent;
      final relationships = _relationships((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/social/reason-reports');
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return gate.future;
      });
      final repository = FakeReasonSharingRepository()
        ..onShared = (query) => ReasonPage(
          items: [_socialReason(reasonId: _reasonA, socialId: null)],
          limit: query.limit,
          nextCursor: null,
        );

      await tester.pumpWidget(
        _app(repository: repository, relationships: relationships),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('reason-report-$_reasonA')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('reason-block-$_reasonA')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('reason-report-$_reasonA')));
      await tester.pumpAndSettle();
      expect(find.text('Why are you reporting this?'), findsOneWidget);
      expect(find.text('Spam'), findsOneWidget);
      expect(find.text('Harassment'), findsOneWidget);
      expect(find.text('Impersonation'), findsOneWidget);
      expect(find.text('Unsafe content'), findsOneWidget);
      expect(find.text('Something else'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('reason-report-category-harassment')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Report this reason?'), findsOneWidget);
      expect(find.byKey(const ValueKey('stock-reason-$_reasonA')), findsOne);

      await tester.tap(
        find.byKey(const ValueKey('reason-safety-confirm-Report')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const ValueKey('stock-reason-$_reasonA')), findsOne);
      expect(sent?['reasonId'], _reasonA);
      expect(sent?['category'], 'harassment');

      gate.complete(
        _json({
          'schemaVersion': 1,
          'report': {
            'reportId': _report,
            'reasonId': _reasonA,
            'category': 'harassment',
            'receivedAt': '2026-09-20T15:00:00.000Z',
          },
        }, 202),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('stock-reason-$_reasonA')),
        findsNothing,
      );
      expect(find.text('No comments yet'), findsOneWidget);
      expect(find.text('Report received.'), findsOneWidget);
    },
  );

  testWidgets('confirmed block removes every row from that public author', (
    tester,
  ) async {
    final calls = <String>[];
    final relationships = _relationships((request) async {
      calls.add('${request.method} ${request.url.path}');
      if (request.method == 'GET') {
        return _json({
          'schemaVersion': 1,
          'block': {
            'socialId': _socialA,
            'revision': 0,
            'blocked': false,
            'updatedAt': null,
          },
        });
      }
      final sent = jsonDecode(request.body) as Map<String, dynamic>;
      return _json({
        'schemaVersion': 1,
        'mutationId': sent['mutationId'],
        'appliedRevision': 1,
        'block': {
          'socialId': _socialA,
          'revision': 1,
          'blocked': true,
          'updatedAt': '2026-09-20T15:10:00.000Z',
        },
      });
    });
    final repository = FakeReasonSharingRepository()
      ..onShared = (query) => ReasonPage(
        items: [
          _socialReason(reasonId: _reasonA, socialId: _socialA),
          _socialReason(reasonId: _reasonB, socialId: _socialA),
          _socialReason(
            reasonId: _reasonC,
            socialId: _socialB,
            handle: 'mira_market',
          ),
        ],
        limit: query.limit,
        nextCursor: null,
      );

    await tester.pumpWidget(
      _app(repository: repository, relationships: relationships),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('reason-block-$_reasonA')));
    await tester.pumpAndSettle();
    expect(find.text('Block @ada_trade?'), findsOneWidget);
    expect(
      find.text(
        'Their reasons will leave this page. Any friendship and open invitations between you will also be removed. Public reasons can still be seen from other accounts.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('reason-safety-confirm-Block')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('stock-reason-$_reasonA')), findsNothing);
    expect(find.byKey(const ValueKey('stock-reason-$_reasonB')), findsNothing);
    expect(
      find.byKey(const ValueKey('stock-reason-$_reasonC')),
      findsOneWidget,
    );
    expect(find.text('@ada_trade blocked.'), findsOneWidget);
    expect(calls, [
      'GET /v1/social/blocks/$_socialA',
      'PUT /v1/social/blocks/$_socialA',
    ]);
  });

  testWidgets('Show more passes the cursor and appends the next page', (
    tester,
  ) async {
    final repository = FakeReasonSharingRepository()
      ..onShared = (query) => query.cursor == null
          ? ReasonPage(
              items: [
                testSharedReason(reasonId: _reasonC),
                testSharedReason(reasonId: _reasonB),
              ],
              limit: query.limit,
              nextCursor: 'cursor-one',
            )
          : ReasonPage(
              items: [testSharedReason(reasonId: _reasonA, handle: 'tobi')],
              limit: query.limit,
              nextCursor: null,
            );
    await tester.pumpWidget(_app(repository: repository, pageSize: 2));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('stock-reason-$_reasonC')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('stock-reason-$_reasonA')), findsNothing);
    final more = find.byKey(const ValueKey('stock-reasons-more'));
    expect(more, findsOneWidget);

    await tester.tap(more);
    await tester.pumpAndSettle();

    expect(repository.sharedQueries, hasLength(2));
    expect(repository.sharedQueries[1].cursor, 'cursor-one');
    expect(repository.sharedQueries[1].limit, 2);
    expect(find.text('@tobi'), findsOneWidget);
    expect(find.byKey(const ValueKey('stock-reasons-more')), findsNothing);
  });

  testWidgets('an offline read shows retry and recovers', (tester) async {
    var reads = 0;
    final repository = FakeReasonSharingRepository()
      ..onShared = (query) {
        reads++;
        if (reads == 1) {
          throw const ReasonSharingException(ReasonSharingFailure.offline);
        }
        return ReasonPage(
          items: [testSharedReason(reasonId: _reasonA)],
          limit: query.limit,
          nextCursor: null,
        );
      };
    await tester.pumpWidget(_app(repository: repository));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('stock-reasons-failed')), findsOneWidget);
    expect(
      find.text('You are offline. Comments couldn’t load.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('stock-reasons-footer')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('stock-reasons-retry')));
    await tester.pumpAndSettle();

    expect(find.text('@ada_trade'), findsOneWidget);
    expect(find.byKey(const ValueKey('stock-reasons-failed')), findsNothing);
  });

  testWidgets('a failed Show more keeps the rows and offers retry', (
    tester,
  ) async {
    var reads = 0;
    final repository = FakeReasonSharingRepository()
      ..onShared = (query) {
        reads++;
        if (reads == 2) {
          throw const ReasonSharingException(ReasonSharingFailure.timeout);
        }
        return ReasonPage(
          items: [testSharedReason(reasonId: reads == 1 ? _reasonB : _reasonA)],
          limit: query.limit,
          nextCursor: reads == 1 ? 'cursor-one' : null,
        );
      };
    await tester.pumpWidget(_app(repository: repository, pageSize: 1));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('stock-reasons-more')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('stock-reason-$_reasonB')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('stock-reasons-more-failed')),
      findsOneWidget,
    );
    expect(find.text('Comments took too long to load.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('stock-reasons-retry')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('stock-reason-$_reasonA')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('stock-reasons-more-failed')),
      findsNothing,
    );
  });

  testWidgets(
    'a private reason of the viewer shows the settings line only when hidden',
    (tester) async {
      var sharedReads = 0;
      final repository = FakeReasonSharingRepository()
        ..onShared = (query) {
          sharedReads++;
          return ReasonPage(
            items: sharedReads == 1
                ? const []
                : [testSharedReason(reasonId: _reasonA, isViewer: true)],
            limit: query.limit,
            nextCursor: null,
          );
        }
        ..onOwn = (query) {
          expect(query.assetId, 'apple');
          expect(query.variantMint, testMint);
          return ReasonPage(
            items: [testOwnReason(reasonId: _reasonA, orderId: _orderA)],
            limit: query.limit,
            nextCursor: null,
          );
        }
        ..privacyReads.add(testPrivacy())
        ..privacyReads.add(
          testPrivacy(revision: 2, visibility: ReasonVisibility.everyone),
        );
      final history = OwnReasonHistory(repository);
      final privacy = ReasonPrivacyController(
        mutationId: () => testReasonMutation,
      );
      addTearDown(privacy.dispose);
      await privacy.bind(principalKey: 'account:one', repository: repository);
      var opened = 0;
      await tester.pumpWidget(
        _app(
          repository: repository,
          ownReasons: history,
          viewerPrivacy: privacy,
          onOpenSettings: () => opened++,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your comment is private.'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('stock-reason-private-settings')),
      );
      expect(opened, 1);
      expect(repository.ownQueries, hasLength(1));

      await privacy.refresh();
      await tester.pumpAndSettle();

      expect(find.text('Your comment is private.'), findsNothing);
      expect(repository.sharedQueries, hasLength(2));
      expect(find.byKey(const ValueKey('stock-reason-$_reasonA')), findsOne);
    },
  );

  testWidgets('exact history invalidation refreshes the mounted stock tab', (
    tester,
  ) async {
    var sharedReads = 0;
    var ownReads = 0;
    final repository = FakeReasonSharingRepository()
      ..onShared = (query) {
        sharedReads++;
        return ReasonPage(
          items: sharedReads == 1
              ? const []
              : [testSharedReason(reasonId: _reasonB)],
          limit: query.limit,
          nextCursor: null,
        );
      }
      ..onOwn = (query) {
        ownReads++;
        return ReasonPage(
          items: ownReads == 1
              ? const []
              : [testOwnReason(reasonId: _reasonA, orderId: _orderA)],
          limit: query.limit,
          nextCursor: null,
        );
      }
      ..privacyReads.add(testPrivacy());
    final history = OwnReasonHistory(repository);
    final privacy = ReasonPrivacyController(
      mutationId: () => testReasonMutation,
    );
    addTearDown(privacy.dispose);
    await privacy.bind(principalKey: 'account:one', repository: repository);
    await tester.pumpWidget(
      _app(repository: repository, ownReasons: history, viewerPrivacy: privacy),
    );
    await tester.pumpAndSettle();

    expect(repository.sharedQueries, hasLength(1));
    expect(repository.ownQueries, hasLength(1));
    expect(find.byKey(const ValueKey('stock-reason-$_reasonB')), findsNothing);
    expect(find.byKey(const ValueKey('stock-reason-private')), findsNothing);

    // ProductApp calls this exact invalidation after a reason is saved.
    history.invalidate(assetId: 'apple', variantMint: testMint);
    await tester.pumpAndSettle();

    expect(repository.sharedQueries, hasLength(2));
    expect(repository.ownQueries, hasLength(2));
    expect(find.byKey(const ValueKey('stock-reason-$_reasonB')), findsOne);
    expect(find.byKey(const ValueKey('stock-reason-private')), findsOne);
  });

  testWidgets('a historical reason of the viewer is not called private', (
    tester,
  ) async {
    final repository = FakeReasonSharingRepository()
      ..onShared = ((query) =>
          ReasonPage(items: const [], limit: query.limit, nextCursor: null))
      ..onOwn = ((query) => ReasonPage(
        items: [
          testOwnReason(
            reasonId: _reasonA,
            orderId: _orderA,
            deskCycle: ReasonDeskCycle.historical,
          ),
        ],
        limit: query.limit,
        nextCursor: null,
      ))
      ..privacyReads.add(testPrivacy());
    final privacy = ReasonPrivacyController(
      mutationId: () => testReasonMutation,
    );
    addTearDown(privacy.dispose);
    await privacy.bind(principalKey: 'account:one', repository: repository);
    await tester.pumpWidget(
      _app(
        repository: repository,
        ownReasons: OwnReasonHistory(repository),
        viewerPrivacy: privacy,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('stock-reason-private')), findsNothing);
  });

  testWidgets('without a privacy read the everyone page decides', (
    tester,
  ) async {
    Future<void> run({required bool viewerShown}) async {
      final repository = FakeReasonSharingRepository()
        ..onShared = ((query) => ReasonPage(
          items: [testSharedReason(reasonId: _reasonA, isViewer: viewerShown)],
          limit: query.limit,
          nextCursor: null,
        ))
        ..onOwn = (query) => ReasonPage(
          items: [testOwnReason(reasonId: _reasonA, orderId: _orderA)],
          limit: query.limit,
          nextCursor: null,
        );
      await tester.pumpWidget(
        _app(repository: repository, ownReasons: OwnReasonHistory(repository)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('stock-reason-private')),
        viewerShown ? findsNothing : findsOneWidget,
      );
    }

    await run(viewerShown: false);
    await run(viewerShown: true);
  });

  test(
    'own history is read once per stock and dropped on invalidate',
    () async {
      var reads = 0;
      final repository = FakeReasonSharingRepository()
        ..onOwn = (query) {
          reads++;
          return ReasonPage(
            items: reads == 1
                ? [testOwnReason(reasonId: _reasonA, orderId: _orderA)]
                : const [],
            limit: query.limit,
            nextCursor: null,
          );
        };
      final history = OwnReasonHistory(repository);

      final first = await history.forStock(
        assetId: 'apple',
        variantMint: testMint,
      );
      final again = await history.forStock(
        assetId: 'apple',
        variantMint: testMint,
      );
      expect(first, hasLength(1));
      expect(identical(first, again), isTrue);
      expect(reads, 1);
      expect(repository.ownQueries.single.limit, reasonPageMaximumLimit);

      history.invalidate(assetId: 'apple', variantMint: testMint);
      expect(
        await history.forStock(assetId: 'apple', variantMint: testMint),
        isEmpty,
      );
      expect(reads, 2);
    },
  );

  test('own history follows the cursor and forgets a failed read', () async {
    var reads = 0;
    final repository = FakeReasonSharingRepository()
      ..onOwn = (query) {
        reads++;
        if (reads == 1) {
          throw const ReasonSharingException(ReasonSharingFailure.offline);
        }
        return query.cursor == null
            ? ReasonPage(
                items: [testOwnReason(reasonId: _reasonB, orderId: _orderA)],
                limit: query.limit,
                nextCursor: 'next',
              )
            : ReasonPage(
                items: [
                  testOwnReason(
                    reasonId: _reasonA,
                    orderId: '55555555-5555-4555-8555-555555555555',
                  ),
                ],
                limit: query.limit,
                nextCursor: null,
              );
      };
    final history = OwnReasonHistory(repository);

    await expectLater(
      history.forStock(assetId: 'apple', variantMint: testMint),
      throwsA(isA<ReasonSharingException>()),
    );
    final items = await history.forStock(
      assetId: 'apple',
      variantMint: testMint,
    );

    expect(items.map((item) => item.reasonId), [_reasonB, _reasonA]);
    expect(repository.ownQueries.last.cursor, 'next');
    expect(reads, 3);
  });

  test('own history fails instead of returning a bounded prefix', () async {
    var reads = 0;
    final repository = FakeReasonSharingRepository()
      ..onOwn = (query) {
        reads++;
        return ReasonPage(
          items: [
            testOwnReason(
              reasonId: reads == 1 ? _reasonB : _reasonA,
              orderId: reads == 1
                  ? _orderA
                  : '55555555-5555-4555-8555-555555555555',
            ),
          ],
          limit: query.limit,
          nextCursor: 'cursor-$reads',
        );
      };
    final history = OwnReasonHistory(repository, maximumPages: 2);

    await expectLater(
      history.forStock(assetId: 'apple', variantMint: testMint),
      throwsA(
        isA<OwnReasonHistoryIncompleteException>().having(
          (error) => error.maximumPages,
          'maximumPages',
          2,
        ),
      ),
    );

    expect(reads, 2);
    expect(repository.ownQueries.map((query) => query.cursor), [
      null,
      'cursor-1',
    ]);
  });

  testWidgets('an incomplete own history is visible instead of guessed', (
    tester,
  ) async {
    final repository = FakeReasonSharingRepository()
      ..onShared = ((query) =>
          ReasonPage(items: const [], limit: query.limit, nextCursor: null))
      ..onOwn = (query) => ReasonPage(
        items: [testOwnReason(reasonId: _reasonA, orderId: _orderA)],
        limit: query.limit,
        nextCursor: 'still-more',
      );

    await tester.pumpWidget(
      _app(
        repository: repository,
        ownReasons: OwnReasonHistory(repository, maximumPages: 1),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('stock-own-reasons-failed')),
      findsOneWidget,
    );
    expect(
      find.text('Your complete reason history could not be loaded here.'),
      findsOneWidget,
    );
  });

  testWidgets('the stock page renders the live tab in the Reasons section', (
    tester,
  ) async {
    final repository = FakeReasonSharingRepository()
      ..onShared = (query) => ReasonPage(
        items: [testSharedReason(reasonId: _reasonA)],
        limit: query.limit,
        nextCursor: null,
      );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, fontFamily: 'Manrope'),
        home: CompanyStockPage(
          details: MarketStockDetails(company: testCompany()),
          orderRepository: FakePaperOrderRepository(),
          clientOrderId: () => 'client-order-1',
          availablePaper: '10000',
          availableShares: '0',
          reasonSharing: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('stock-section-reasons')),
    );
    await tester.tap(find.byKey(const ValueKey('stock-section-reasons')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('@ada_trade'));
    expect(find.text('@ada_trade'), findsOneWidget);
    expect(find.text('Margins improved for a second quarter.'), findsOneWidget);
    expect(
      find.text('Only people who chose Everyone show here.'),
      findsNothing,
    );
    expect(repository.sharedQueries.single.variantMint, testMint);
  });
}

Widget _app({
  required ReasonSharingRepository? repository,
  OwnReasonHistory? ownReasons,
  ReasonPrivacyController? viewerPrivacy,
  RelationshipsController? relationships,
  VoidCallback? onOpenSettings,
  int pageSize = 20,
}) => MaterialApp(
  theme: ThemeData(useMaterial3: true, fontFamily: 'Manrope'),
  home: Scaffold(
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        StockReasonsTab(
          repository: repository,
          assetId: 'apple',
          variantMint: testMint,
          ownReasons: ownReasons,
          viewerPrivacy: viewerPrivacy,
          relationships: relationships,
          onOpenSettings: onOpenSettings,
          pageSize: pageSize,
        ),
      ],
    ),
  ),
);

RelationshipsController _relationships(
  Future<http.Response> Function(http.Request request) route,
) {
  final transport = MockClient(route);
  final controller = RelationshipsController(
    client: HttpRelationshipsClient(
      client: transport,
      baseUri: Uri.parse('https://api.example'),
      accountId: _account,
      accessToken: () async => const PracticeAccessToken(
        accountId: _account,
        token: 'header.payload.signature',
      ),
    ),
  );
  addTearDown(() {
    controller.dispose();
    transport.close();
  });
  return controller;
}

SharedReason _socialReason({
  required String reasonId,
  required String? socialId,
  String handle = 'ada_trade',
}) => SharedReason(
  reasonId: reasonId,
  author: ReasonAuthor(
    handle: handle,
    rank: CareerRank.analyst,
    rankLabel: 'Analyst',
    isViewer: false,
    socialId: socialId,
    persona: socialId == null ? null : 'oracle',
  ),
  stock: testReasonStock,
  note: 'Margins improved for a second quarter.',
  savedAt: DateTime.utc(2026, 9, 20, 12),
);

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);
