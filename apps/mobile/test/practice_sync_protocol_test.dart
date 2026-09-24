import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/design_study/progress.dart';
import 'package:trimmy/practice_sync/protocol.dart';

const _mutationId = 'ABCDEF01-2345-6789-ABCD-EF0123456789';
const _serverTime = '2026-09-14T10:20:30.123Z';

Map<String, dynamic> _snapshot([Object? progress]) => {
  'schemaVersion': 1,
  'revision': 1,
  'progress': progress ?? OfficeProgress.empty().toJson(),
  'updatedAt': _serverTime,
};

Map<String, dynamic> _mutation([Object? progress]) => {
  'schemaVersion': 1,
  'mutationId': _mutationId,
  'baseRevision': 0,
  'progress': progress ?? OfficeProgress.empty().toJson(),
};

final _invalid = throwsA(
  isA<PracticeSyncException>().having(
    (error) => error.code,
    'code',
    'PRACTICE_INVALID_PROTOCOL',
  ),
);

Object? _reverseKeys(Object? input) {
  if (input is Map<String, dynamic>) {
    return {
      for (final key in input.keys.toList().reversed)
        key: _reverseKeys(input[key]),
    };
  }
  return input;
}

void main() {
  final cases = <Map<String, dynamic>>[
    for (final version in [3, 4])
      for (final entry
          in (jsonDecode(
                    File(
                      '../../contracts/practice-progress-v$version.json',
                    ).readAsStringSync(),
                  )
                  as Map<String, dynamic>)['cases']
              as List)
        {
          ...entry as Map<String, dynamic>,
          'name': 'v$version-${entry['name']}',
        },
  ];

  for (final entry in cases.cast<Map<String, dynamic>>()) {
    test('native contract round trip: ${entry['name']}', () {
      final input = entry['progress'] as Map<String, dynamic>;
      final snapshot = PracticeSnapshot.fromJson(_snapshot(input));
      final mutation = PracticeMutation.fromJson(_mutation(input));
      expect(snapshot.toJson(), _snapshot(input));
      expect(mutation.toJson(), {
        ..._mutation(input),
        'mutationId': _mutationId.toLowerCase(),
      });
      expect(
        PracticeSnapshot.fromJson(snapshot.toJson()).toJson(),
        snapshot.toJson(),
      );
      expect(
        PracticeMutation.fromJson(mutation.toJson()).toJson(),
        mutation.toJson(),
      );
      final reversed = OfficeProgress.fromJson(
        _reverseKeys(input) as Map<String, dynamic>,
      );
      expect(
        canonicalProgress(reversed),
        canonicalProgress(snapshot.progress!),
      );
      expect(snapshot.progress!.toJson(), input);
    });
  }

  test('empty account and an explicitly saved empty progress are distinct', () {
    final empty = PracticeSnapshot(
      revision: 0,
      progress: null,
      updatedAt: null,
    );
    expect(PracticeSnapshot.fromJson(empty.toJson()).toJson(), {
      'schemaVersion': 1,
      'revision': 0,
      'progress': null,
      'updatedAt': null,
    });
    final saved = PracticeSnapshot.fromJson(_snapshot());
    expect(saved.progress, isNotNull);
    for (final input in [
      {..._snapshot(), 'revision': 0},
      {..._snapshot(), 'progress': null},
      {..._snapshot(), 'updatedAt': null},
      {...empty.toJson(), 'updatedAt': _serverTime},
    ]) {
      expect(() => PracticeSnapshot.fromJson(input), _invalid);
    }
  });

  test('safe integer revisions are enforced on read and construction', () {
    expect(
      PracticeSnapshot.fromJson({
        ..._snapshot(),
        'revision': practiceMaxRevision,
      }).revision,
      practiceMaxRevision,
    );
    expect(
      PracticeMutation.fromJson({
        ..._mutation(),
        'baseRevision': practiceMaxRevision,
      }).baseRevision,
      practiceMaxRevision,
    );
    for (final revision in [
      -1,
      practiceMaxRevision + 1,
      1.0,
      '1',
      null,
      true,
    ]) {
      expect(
        () => PracticeSnapshot.fromJson({..._snapshot(), 'revision': revision}),
        _invalid,
      );
      expect(
        () => PracticeMutation.fromJson({
          ..._mutation(),
          'baseRevision': revision,
        }),
        _invalid,
      );
    }
    expect(
      () => PracticeMutation(
        mutationId: _mutationId,
        baseRevision: -1,
        progress: OfficeProgress.empty(),
      ),
      _invalid,
    );
    expect(
      () => PracticeSnapshot(
        revision: 0,
        progress: OfficeProgress.empty(),
        updatedAt: null,
      ),
      _invalid,
    );
  });

  test('wrappers reject unknown, missing, wrongly typed and future fields', () {
    for (final parser in [
      PracticeSnapshot.fromJson,
      PracticeMutation.fromJson,
    ]) {
      final valid = parser == PracticeSnapshot.fromJson
          ? _snapshot()
          : _mutation();
      for (final field in valid.keys) {
        expect(() => parser({...valid}..remove(field)), _invalid);
      }
      for (final version in [0, 2, 1.0, '1', true, null]) {
        expect(() => parser({...valid, 'schemaVersion': version}), _invalid);
      }
      expect(() => parser({...valid, 'userId': 'forged'}), _invalid);
      for (final malformed in [null, [], 'payload', 1]) {
        expect(() => parser(malformed), _invalid);
      }
    }
  });

  test('native local migrations are never silently accepted over the wire', () {
    for (final version in [1, 2, 7, 3.0, 4.0, 5.0, '3', null]) {
      final progress = {...OfficeProgress.empty().toJson(), 'version': version};
      expect(() => PracticeSnapshot.fromJson(_snapshot(progress)), _invalid);
      expect(() => PracticeMutation.fromJson(_mutation(progress)), _invalid);
    }
    final invalidStates = [
      {...OfficeProgress.empty().toJson(), 'token': 'private'},
      {
        ...OfficeProgress.empty().toJson(),
        'active': {
          'activityId': 'sales-and-profit',
          'stage': 2,
          'selectedChoiceId': 'check-costs',
          'corrected': false,
          'answerParts': <String, String>{},
        },
      },
      {
        ...OfficeProgress.empty().toJson(),
        'completions': {'unexpected': 'é' * practiceMaxProgressBytes},
      },
    ];
    for (final progress in invalidStates) {
      expect(() => PracticeSnapshot.fromJson(_snapshot(progress)), _invalid);
      expect(() => PracticeMutation.fromJson(_mutation(progress)), _invalid);
    }
  });

  test('server dates require exact UTC millisecond calendar timestamps', () {
    for (final time in [
      '2026-02-30T10:20:30.123Z',
      '2026-09-14T24:20:30.123Z',
      '2026-09-14T10:20:60.123Z',
      '2026-09-14T10:20:30Z',
      '2026-09-14T10:20:30.123000Z',
      '2026-09-14T10:20:30.123456Z',
      '2026-09-14T10:20:30.123+00:00',
      '2026-09-14T10:20:30.123',
      '$_serverTime\n',
      0,
    ]) {
      expect(
        () => PracticeSnapshot.fromJson({..._snapshot(), 'updatedAt': time}),
        _invalid,
      );
    }
    expect(
      () => PracticeSnapshot(
        revision: 1,
        progress: OfficeProgress.empty(),
        updatedAt: DateTime.utc(2026, 9, 14, 10, 20, 30, 123, 456),
      ),
      _invalid,
    );
    expect(
      () => PracticeSnapshot(
        revision: 1,
        progress: OfficeProgress.empty(),
        updatedAt: DateTime(2026, 9, 14),
      ),
      _invalid,
    );
  });

  test(
    'mutation UUID is exact shape, canonicalized, and never authentication',
    () {
      expect(normalizePracticeUuid(_mutationId), _mutationId.toLowerCase());
      for (final id in [
        '',
        'user-123',
        ' $_mutationId',
        '$_mutationId\n',
        _mutationId.replaceFirst('A', 'G'),
        123,
        null,
      ]) {
        expect(
          () => PracticeMutation.fromJson({..._mutation(), 'mutationId': id}),
          _invalid,
        );
      }
      expect(
        () => PracticeMutation(
          mutationId: 'invalid',
          baseRevision: 0,
          progress: OfficeProgress.empty(),
        ),
        _invalid,
      );
    },
  );

  test('validated objects cannot be changed through caller JSON maps', () {
    final input = _snapshot(
      OfficeProgress.empty()
          .startActivity(OfficeActivityIds.checkTheDate)
          .toJson(),
    );
    final snapshot = PracticeSnapshot.fromJson(input);
    final original = canonicalProgress(snapshot.progress!);
    (input['progress'] as Map)['active'] = null;
    (snapshot.toJson()['progress'] as Map)['active'] = null;
    expect(canonicalProgress(snapshot.progress!), original);
    final conflict = PracticeRevisionConflict(snapshot);
    expect(conflict.currentSnapshot, same(snapshot));
    expect(
      conflict.toString(),
      'PracticeSyncException(PRACTICE_REVISION_CONFLICT)',
    );
  });
}
