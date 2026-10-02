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
  DailyDeskRepository(
    this.origin,
    this.authorization, {
    http.Client? client,
    this.language,
  }) : _client = client ?? http.Client() {
    if (origin.scheme != 'https' || origin.userInfo.isNotEmpty) {
      throw ArgumentError('HTTPS required');
    }
  }
  final Uri origin;
  final Future<PaperAuthorization> Function() authorization;
  final http.Client _client;

  /// The story language to ask for: es, pt or fr, or null for English.
  final String? Function()? language;
  bool _closed = false;

  /// Set once an API from before story languages has refused `lang`.
  bool _languageRefused = false;
  void close() {
    _closed = true;
    _client.close();
  }

  Future<DailyShift> read() => _request();
  Future<DailyShift> complete(DailyShift shift, String choice) => _request(
    body: {'date': shift.date, 'caseId': shift.caseId, 'choiceId': choice},
  );

  /// A story request in the reader's language. An API from before story
  /// languages refuses `lang` while checking the request, before anything is
  /// read or saved, so the same request is sent again without it.
  Future<DailyShift> _request({Map<String, String>? body}) async {
    final lang = _languageRefused ? null : language?.call();
    if (lang == null) return _send(body, null);
    try {
      return await _send(body, lang);
    } on DailyDeskException catch (error) {
      if (error.code != 'INVALID_REQUEST') rethrow;
      final shift = await _send(body, null);
      _languageRefused = true;
      return shift;
    }
  }

  Future<DailyShift> _send(Map<String, String>? body, String? lang) async {
    final auth = await authorization();
    if (_closed) throw const DailyDeskException('SESSION_CHANGED');
    final target = origin.resolve(
      '/v1/career/daily-desk${body == null ? '' : '/complete'}',
    );
    final request =
        http.Request(
            body == null ? 'GET' : 'POST',
            lang == null
                ? target
                : target.replace(queryParameters: {'lang': lang}),
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

  /// The last read failed. The text is chosen where it shows, in the app's
  /// language.
  bool failed = false;
  int _epoch = 0;
  Future<void>? _refresh;
  Future<void> refresh() =>
      _refresh ??= _load().whenComplete(() => _refresh = null);
  Future<void> _load() async {
    if (closed) return;
    final epoch = _epoch;
    loading = true;
    failed = false;
    notifyListeners();
    try {
      final next = await repository.read();
      if (!closed && epoch == _epoch) shift = next;
    } catch (_) {
      if (!closed && epoch == _epoch) failed = true;
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
    failed = false;
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
