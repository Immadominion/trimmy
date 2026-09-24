import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../design_study/progress.dart';
import '../practice_sync/account_progress_session.dart';
import '../social/invitation_create_store.dart';
import '../social/relationship_mutation_store.dart';
import 'account_controller.dart';
import 'auth.dart';
import 'config.dart';
import 'guest_session.dart';
import 'privy_auth.dart';

/// Owns native integration resources for the lifetime of the application.
/// Browser previews and unconfigured builds remain usable as guest practice.
class PracticeAccountHost extends StatefulWidget {
  const PracticeAccountHost({
    super.key,
    required this.preferences,
    required this.builder,
    this.controller,
  });

  final SharedPreferences preferences;
  final Widget Function(BuildContext, AccountController?, bool) builder;
  final AccountController? controller;

  @override
  State<PracticeAccountHost> createState() => _PracticeAccountHostState();
}

class _PracticeAccountHostState extends State<PracticeAccountHost>
    with WidgetsBindingObserver {
  AccountController? _controller;
  PracticeAuth? _auth;
  http.Client? _client;
  bool _configurationFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = widget.controller;
    if (_controller == null) {
      try {
        final config = PracticeAccountConfig.fromEnvironment();
        if (config.enabled) {
          _auth = createPracticeAuth(config);
          _client = http.Client();
          final guestSessions = GuestSessionController(
            store: SecureGuestCredentialStore(),
            client: HttpGuestSessionClient(
              client: _client!,
              baseUri: config.apiUri!,
            ),
          );
          _controller = AccountController(
            auth: _auth!,
            guestRepository: OfficeProgressRepository.fromPreferences(
              widget.preferences,
            ),
            store: PreferencesPracticeSyncStore(widget.preferences),
            httpClient: _client!,
            baseUri: config.apiUri!,
            bindingAppId: config.appId!,
            guestSessions: guestSessions,
            invitationCreateMutationStore:
                PreferencesInvitationCreateMutationStore(widget.preferences),
            relationshipMutationStore: PreferencesRelationshipMutationStore(
              widget.preferences,
            ),
          );
        }
      } on PracticeConfigurationException {
        _configurationFailed = true;
      }
    }
    _controller?.addListener(_changed);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _controller?.setForeground(
      lifecycle == null || lifecycle == AppLifecycleState.resumed,
    );
    unawaited(_controller?.initialize());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _controller?.setForeground(state == AppLifecycleState.resumed);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_changed);
    if (widget.controller == null) {
      _controller?.dispose();
      unawaited(_auth?.close());
      _client?.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _controller, _configurationFailed);
}
