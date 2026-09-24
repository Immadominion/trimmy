import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../account/guest_session.dart';

class WorkAssignment {
  WorkAssignment(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  int get ordinal => data['ordinal'] as int;
  String get title => data['title'] as String;
  String get brief => data['brief'] as String;
  String get speaker => data['speaker'] as String;
  String get art => data['art'] as String;
  String get district => data['district'] as String;
  int get step => data['step'] as int? ?? 0;
  int get revision => data['revision'] as int? ?? 0;
  String get draft => data['draft'] as String? ?? '';
  bool get complete => data['completedAt'] != null;
  Map<String, dynamic> get evidence =>
      Map<String, dynamic>.from(data['evidence'] as Map);
  Map<String, dynamic> get decision =>
      Map<String, dynamic>.from(data['decision'] as Map);
  Map<String, dynamic> get file =>
      Map<String, dynamic>.from(data['file'] as Map);
  List<Map<String, dynamic>> get rows => (data['rows'] as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  String get portrait => speaker == 'sal'
      ? 'assets/images/ui_review/sal/sal-teaching-v2.png'
      : 'assets/images/ui_review/persona-$speaker-avatar-v1.png';
}

class WorkJourney {
  WorkJourney.fromJson(Map<String, dynamic> json)
    : assignments = (json['assignments'] as List)
          .map((e) => WorkAssignment(Map<String, dynamic>.from(e as Map)))
          .toList() {
    if (assignments.isEmpty ||
        assignments.length > 200 ||
        assignments.map((e) => e.id).toSet().length != assignments.length) {
      throw const FormatException('Invalid assignments');
    }
  }
  final List<WorkAssignment> assignments;
  WorkAssignment? get current =>
      assignments.where((e) => !e.complete).firstOrNull;
  WorkAssignment? find(String id) =>
      assignments.where((e) => e.id == id).firstOrNull;
  bool unlocked(WorkAssignment item) => item.complete || current?.id == item.id;
}

class WorkdayException implements Exception {
  const WorkdayException(this.code);
  final String code;
  String get message => switch (code) {
    'CHECK_EVIDENCE' =>
      'Check the source again. Those details don’t support this update.',
    'CHECK_DECISION' => 'Take another look at the figures.',
    'WORK_CHANGED' =>
      'Your work changed on another screen. We’ve refreshed it.',
    'WORK_LOCKED' => 'File the earlier assignment first.',
    'SESSION_CHANGED' => 'Your account changed. Open your desk again.',
    _ => 'Couldn’t save yet. Your work is still here—try again.',
  };
}

class WorkdayRepository {
  WorkdayRepository(this.origin, this.authorization, {http.Client? client})
    : _client = client ?? http.Client() {
    if (origin.scheme != 'https' || origin.userInfo.isNotEmpty) {
      throw ArgumentError('HTTPS required');
    }
  }
  final Uri origin;
  final Future<PaperAuthorization> Function() authorization;
  final http.Client _client;
  bool _closed = false;
  void close() {
    _closed = true;
    _client.close();
  }

  Future<WorkJourney> read() => _request('');
  Future<WorkJourney> save(
    WorkAssignment assignment,
    Map<String, dynamic> answer, {
    String? draft,
  }) => _request('/step', {
    'assignmentId': assignment.id,
    'revision': assignment.revision,
    'step': assignment.step,
    'answer': answer,
    'draft': ?draft,
  });
  Future<WorkJourney> saveDraft(WorkAssignment assignment, String draft) =>
      _request('/draft', {
        'assignmentId': assignment.id,
        'revision': assignment.revision,
        'draft': draft,
      });
  Future<WorkJourney> _request(
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final auth = await authorization();
    if (_closed) throw const WorkdayException('SESSION_CHANGED');
    final request =
        http.Request(
            body == null ? 'GET' : 'POST',
            origin.resolve('/v1/career/workdays$path'),
          )
          ..followRedirects = false
          ..headers.addAll({
            'authorization': auth.headerValue,
            'accept': 'application/json',
          });
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 12));
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 12),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > 524288) {
        throw const FormatException('Response too large');
      }
    }
    if (_closed) throw const WorkdayException('SESSION_CHANGED');
    if (response.statusCode != 200) {
      String code = 'WORK_UNAVAILABLE';
      try {
        code =
            (jsonDecode(utf8.decode(bytes)) as Map)['code'] as String? ?? code;
      } catch (_) {}
      throw WorkdayException(code);
    }
    return WorkJourney.fromJson(
      Map<String, dynamic>.from(
        (jsonDecode(utf8.decode(bytes)) as Map)['journey'] as Map,
      ),
    );
  }
}

class WorkdayController extends ChangeNotifier {
  WorkdayController(this.repository);
  final WorkdayRepository repository;
  WorkJourney? journey;
  bool loading = false, closed = false;
  String? error;
  Future<void> _queue = Future<void>.value();
  Future<void>? _refresh;
  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _queue.then((_) {
      if (closed) throw const WorkdayException('SESSION_CHANGED');
      return operation();
    });
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _accept(WorkJourney next) {
    if (closed) throw const WorkdayException('SESSION_CHANGED');
    journey = next;
    error = null;
    notifyListeners();
  }

  Future<void> refresh() => _refresh ??= _serial(() async {
    loading = true;
    notifyListeners();
    try {
      _accept(await repository.read());
    } catch (_) {
      if (!closed) error = 'Your assignments couldn’t load.';
    } finally {
      if (!closed) {
        loading = false;
        notifyListeners();
      }
    }
  }).whenComplete(() => _refresh = null);
  Future<void> save(
    WorkAssignment original,
    Map<String, dynamic> answer, {
    String? draft,
  }) => _serial(() async {
    final latest = journey?.find(original.id) ?? original;
    // A draft may have advanced the revision, but never silently submit another stage.
    if (latest.step != original.step) {
      throw const WorkdayException('WORK_CHANGED');
    }
    try {
      _accept(await repository.save(latest, answer, draft: draft));
    } on WorkdayException catch (e) {
      if (e.code == 'WORK_CHANGED') _accept(await repository.read());
      rethrow;
    }
  });
  Future<void> draft(String id, String text) => _serial(() async {
    final latest = journey?.find(id);
    if (latest == null ||
        latest.step != 2 ||
        latest.complete ||
        latest.draft == text) {
      return;
    }
    _accept(await repository.saveDraft(latest, text));
  });
  @override
  void dispose() {
    closed = true;
    repository.close();
    super.dispose();
  }
}
