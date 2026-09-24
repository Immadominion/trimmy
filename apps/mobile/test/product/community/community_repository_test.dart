import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/account/guest_session.dart';
import 'package:trimmy/product/community/community.dart';

void main() {
  test(
    'community requires account auth and never redirects credentials',
    () async {
      var sent = 0;
      final client = MockClient((request) async {
        sent++;
        expect(request.followRedirects, isFalse);
        expect(request.headers['authorization'], 'Bearer fresh');
        return http.Response('{"items":[],"next":null}', 200);
      });
      PaperAuthorization auth = const GuestPaperAuthorization('guest');
      final repository = CommunityRepository(
        Uri.parse('https://api.example.test'),
        () async => auth,
        client: client,
      );
      await expectLater(repository.read('everyone'), throwsStateError);
      expect(sent, 0);
      auth = const PrivyPaperAuthorization('fresh');
      expect((await repository.read('following')).posts, isEmpty);
      expect(sent, 1);
      repository.close();
      await expectLater(repository.read('everyone'), throwsStateError);
      expect(sent, 1);
    },
  );
  test('late response from a closed identity is discarded', () async {
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final repo = CommunityRepository(
      Uri.parse('https://api.example.test'),
      () async => const PrivyPaperAuthorization('token'),
      client: MockClient((_) {
        started.complete();
        return response.future;
      }),
    );
    final read = repo.read('everyone');
    final rejected = expectLater(read, throwsStateError);
    await started.future;
    repo.close();
    response.complete(http.Response('{"items":[],"next":null}', 200));
    await rejected;
  });
  test(
    'follow and mute send desired state without publishing trade data',
    () async {
      final post = CommunityPost.fromJson({
        'reasonId': 'reason',
        'socialId': 'author',
        'handle': 'trader',
        'persona': null,
        'assetId': 'apple',
        'symbol': 'AAPL',
        'note': 'A public comment',
        'savedAt': '2026-09-24T12:00:00Z',
        'following': false,
        'notifications': false,
        'isViewer': false,
      });
      final repo = CommunityRepository(
        Uri.parse('https://api.example.test'),
        () async => const PrivyPaperAuthorization('token'),
        client: MockClient((request) async {
          expect(request.method, 'PUT');
          expect(request.url.path, '/v1/community/following/author');
          expect(jsonDecode(request.body), {
            'following': true,
            'notifications': false,
          });
          return http.Response('{"following":true}', 200);
        }),
      );
      addTearDown(repo.close);
      await repo.follow(post, following: true, notifications: false);
    },
  );
}
