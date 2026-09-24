import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:trimmy/design_study/progress.dart';
import 'package:trimmy/practice_sync/account_progress_session.dart';
import 'package:trimmy/practice_sync/durable_state.dart';
import 'package:trimmy/practice_sync/http_transport.dart';
import 'package:trimmy/practice_sync/protocol.dart';

class _DiskStore implements PracticeSyncStore {
  _DiskStore(this.directory);
  final Directory directory;
  @override
  Future<String?> read(String key) async {
    final file = File('${directory.path}/$key');
    return await file.exists() ? file.readAsString() : null;
  }

  @override
  Future<bool> write(String key, String value) async {
    final file = File('${directory.path}/$key');
    final staging = File('${file.path}.pending');
    await staging.writeAsString(value, flush: true);
    await staging.rename(file.path);
    return true;
  }
}

/// Lose the first PUT reply after the actual API has committed its transaction.
class _LoseReplyClient extends http.BaseClient {
  _LoseReplyClient(this.inner);
  final http.Client inner;
  bool lost = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await inner.send(request);
    if (!lost && request.method == 'PUT' && response.statusCode == 200) {
      lost = true;
      await response.stream.drain<void>();
      throw http.ClientException('Simulated lost response');
    }
    return response;
  }

  @override
  void close() => inner.close();
}

void main() {
  test(
    'mobile disk queue, real HTTP, verified sessions and PostgreSQL recover one uncertain completion',
    () async {
      final address = Platform.environment['TRIMMY_SYNC_TEST_API'];
      final token = Platform.environment['TRIMMY_SYNC_TEST_TOKEN'];
      final otherToken = Platform.environment['TRIMMY_SYNC_TEST_OTHER_TOKEN'];
      expect(
        address,
        isNotNull,
        reason: 'Run npm run test:mobile-sync from trimmy/.',
      );
      expect(token, isNotNull);
      expect(otherToken, isNotNull);
      final uri = Uri.parse(address!);
      expect(uri.host, '127.0.0.1');
      final directory = await Directory.systemTemp.createTemp(
        'trimmy-sync-contract-',
      );
      final client = _LoseReplyClient(IOClient(HttpClient()));
      try {
        final sessions = HttpPracticeSessionClient(
          client: client,
          baseUri: uri,
          accessToken: () async => token!,
          allowLoopbackForTests: true,
        );
        final accountId = await sessions.openSession();
        expect(await sessions.openSession(), accountId);
        final transport = HttpPracticeTransport(
          client: client,
          baseUri: uri,
          accountId: accountId,
          accessToken: () async =>
              PracticeAccessToken(accountId: accountId, token: token!),
          allowLoopbackForTests: true,
        );
        var session = await AccountProgressSession.open(
          accountId: accountId,
          store: _DiskStore(directory),
          transport: transport,
          clock: () => DateTime.utc(2026, 9, 14, 17, 0, 0, 123, 456),
        );
        final repository = session.progressRepository;
        await repository.startActivity(OfficeActivityIds.checkTheDate);
        await repository.advance();
        await repository.advance();
        await repository.selectChoice('keep-headline');
        await repository.submitChoice();
        await repository.acceptCorrection();
        final original = repository.state.toJson();
        await expectLater(
          session.synchronize(),
          throwsA(isA<PracticeSyncException>()),
        );
        expect(client.lost, isTrue);
        final pending = session.coordinator.state!.pending!.toJson();
        expect((await transport.getProgress()).revision, 1);
        session.close();

        // New coordinator/store instances read the same on-disk uncertain intent.
        session = await AccountProgressSession.open(
          accountId: accountId,
          store: _DiskStore(directory),
          transport: transport,
        );
        expect(session.coordinator.state!.pending!.toJson(), pending);
        await session.synchronize();
        expect(session.coordinator.state!.pending, isNull);
        expect(session.progressRepository.state.toJson(), original);
        expect((await transport.getProgress()).revision, 1);
        await session.progressRepository.closeActivity();
        await session.synchronize();
        expect((await transport.getProgress()).revision, 2);

        final freshDirectory = await Directory.systemTemp.createTemp(
          'trimmy-sync-restore-',
        );
        try {
          final restored = await AccountProgressSession.open(
            accountId: accountId,
            store: _DiskStore(freshDirectory),
            transport: transport,
          );
          await restored.synchronize();
          expect(
            restored.progressRepository.state.toJson(),
            session.progressRepository.state.toJson(),
          );
          expect(
            restored
                .progressRepository
                .state
                .completions
                .values
                .single
                .completedAt!
                .toIso8601String(),
            '2026-09-14T17:00:00.123456Z',
          );
          restored.close();
        } finally {
          await freshDirectory.delete(recursive: true);
        }

        final otherId = await HttpPracticeSessionClient(
          client: client,
          baseUri: uri,
          accessToken: () async => otherToken!,
          allowLoopbackForTests: true,
        ).openSession();
        expect(otherId, isNot(accountId));
        final otherTransport = HttpPracticeTransport(
          client: client,
          baseUri: uri,
          accountId: otherId,
          accessToken: () async =>
              PracticeAccessToken(accountId: otherId, token: otherToken!),
          allowLoopbackForTests: true,
        );
        expect((await otherTransport.getProgress()).revision, 0);
        session.close();
      } finally {
        client.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
