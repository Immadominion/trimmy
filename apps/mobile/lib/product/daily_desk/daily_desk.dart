import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../account/guest_session.dart';

class DeskChoice {
  DeskChoice.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      label = json['label'] as String,
      outcome = json['outcome'] as String,
      takeaway = json['takeaway'] as String;
  final String id, label, outcome, takeaway;
}

class DailyShift {
  DailyShift.fromJson(Map<String, dynamic> json)
    : date = json['date'] as String,
      caseId = (json['story'] as Map)['id'] as String,
      title = (json['story'] as Map)['title'] as String,
      speaker = (json['story'] as Map)['speaker'] as String,
      body = (json['story'] as Map)['body'] as String,
      choices = ((json['story'] as Map)['choices'] as List)
          .map((e) => DeskChoice.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false),
      completedChoice = json['completedChoice'] as String?,
      history = (json['history'] as List)
          .map((e) => (e as Map)['date'] as String)
          .toSet() {
    if (choices.length != 3 ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        (completedChoice != null &&
            !choices.any((c) => c.id == completedChoice))) {
      throw const FormatException('Invalid desk story');
    }
  }
  final String date, caseId, title, speaker, body;
  final List<DeskChoice> choices;
  final String? completedChoice;
  final Set<String> history;
  bool get complete => completedChoice != null;
  DeskChoice? get result =>
      choices.where((c) => c.id == completedChoice).firstOrNull;
  String get portrait => speaker == 'sal'
      ? 'assets/images/ui_review/sal/sal-teaching-v2.png'
      : 'assets/images/ui_review/persona-$speaker-avatar-v1.png';
}

class DailyDeskException implements Exception {
  const DailyDeskException(this.code);
  final String code;
}

class DailyDeskRepository {
  DailyDeskRepository(this.origin, this.authorization, {http.Client? client})
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

  Future<DailyShift> read() => _request();
  Future<DailyShift> complete(DailyShift shift, String choice) => _request(
    body: {'date': shift.date, 'caseId': shift.caseId, 'choiceId': choice},
  );
  Future<DailyShift> _request({Map<String, String>? body}) async {
    final auth = await authorization();
    if (_closed) throw const DailyDeskException('SESSION_CHANGED');
    final request =
        http.Request(
            body == null ? 'GET' : 'POST',
            origin.resolve(
              '/v1/career/daily-desk${body == null ? '' : '/complete'}',
            ),
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
      if (bytes.length > 65536) {
        throw const FormatException('Response too large');
      }
    }
    if (_closed) throw const DailyDeskException('SESSION_CHANGED');
    if (response.statusCode != 200) {
      String code = 'UNAVAILABLE';
      try {
        code =
            (jsonDecode(utf8.decode(bytes)) as Map)['code'] as String? ?? code;
      } catch (_) {}
      throw DailyDeskException(code);
    }
    return DailyShift.fromJson(
      (jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>)['shift']
          as Map<String, dynamic>,
    );
  }
}

class DailyDeskController extends ChangeNotifier {
  DailyDeskController(this.repository);
  final DailyDeskRepository repository;
  DailyShift? shift;
  bool loading = false, closed = false;
  String? error;
  int _epoch = 0;
  Future<void>? _refresh;
  Future<void> refresh() =>
      _refresh ??= _load().whenComplete(() => _refresh = null);
  Future<void> _load() async {
    if (closed) return;
    final epoch = _epoch;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final next = await repository.read();
      if (!closed && epoch == _epoch) shift = next;
    } catch (_) {
      if (!closed && epoch == _epoch) error = 'Your desk story couldn’t load.';
    }
    if (!closed) {
      loading = false;
      notifyListeners();
    }
  }

  Future<DailyShift> complete(DailyShift original, String choice) async {
    // Finish an in-flight read first so an older response cannot erase completion.
    await _refresh;
    _epoch++;
    final next = await repository.complete(original, choice);
    if (closed) throw const DailyDeskException('SESSION_CHANGED');
    _epoch++;
    shift = next;
    error = null;
    notifyListeners();
    return next;
  }

  @override
  void dispose() {
    closed = true;
    repository.close();
    super.dispose();
  }
}
