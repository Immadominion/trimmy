import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/account/account_controller.dart';
import 'package:trimmy/account/account_data.dart';
import 'package:trimmy/account/guest_session.dart';
import 'package:trimmy/account/wallet_setup.dart';
import 'package:trimmy/l10n/l10n.dart';
import 'package:trimmy/practice_sync/http_transport.dart';
import 'package:trimmy/product/account/fund_wallet_sheet.dart';
import 'package:trimmy/product/account/guest_desk_preserved_screen.dart';
import 'package:trimmy/product/account/guest_desk_recovery_screen.dart';
import 'package:trimmy/product/account/product_sign_in_screen.dart';
import 'package:trimmy/product/account/sign_in_methods_page.dart';
import 'package:trimmy/product/desk/desk_models.dart';
import 'package:trimmy/product/desk/desk_screen.dart';
import 'package:trimmy/product/desk/wall_street_clock.dart';
import 'package:trimmy/product/floor/floor_screen.dart';
import 'package:trimmy/product/market/fast_buy_sheet.dart';
import 'package:trimmy/product/market/live_order_flow.dart';
import 'package:trimmy/product/market/live_trading.dart';
import 'package:trimmy/product/market/market.dart';
import 'package:trimmy/product/money/live_trade_history.dart';
import 'package:trimmy/product/money/real_holdings.dart';
import 'package:trimmy/product/money/send_money_flow.dart';
import 'package:trimmy/product/onboarding/first_stock_followup.dart';
import 'package:trimmy/product/onboarding/onboarding.dart';
import 'package:trimmy/product/profile/profile_screen.dart';
import 'package:trimmy/product/settings/language_settings.dart';
import 'package:trimmy/product/settings/product_information_screen.dart';
import 'package:trimmy/product/settings/settings.dart';
import 'package:trimmy/product/shell/product_shell.dart';
import 'package:trimmy/product/workdays/career_world.dart';
import 'package:trimmy/product/workdays/workday_screen.dart';
import 'package:trimmy/product/workdays/workdays.dart';
import 'package:trimmy/ui_review/review_welcome_note.dart';

import '../../support/account_data_fixtures.dart' as fixtures;
import '../../support/l10n_harness.dart';
import '../market/live_trading_test_support.dart';
import '../market/market_test_support.dart';

/// What a screen is built from: the language under test, and a place to
/// register clean-up for controllers and repositories the screen needs.
class L10nScreenContext {
  L10nScreenContext(this.locale, this.preferences)
    : l10n = lookupAppLocalizations(locale),
      formats = AppFormats.forLocale(locale);

  final Locale locale;
  final AppLocalizations l10n;
  final AppFormats formats;
  final SharedPreferences preferences;
  final _disposers = <VoidCallback>[];
  void dispose(VoidCallback disposer) => _disposers.add(disposer);
}

/// One production screen as the localization tests pump it, with the app's
/// own text for anything production hands the screen ready-made.
class L10nScreen {
  const L10nScreen(this.name, this.build, {this.reveal});
  final String name;
  final Widget Function(L10nScreenContext context) build;

  /// Taps after the first frame that open more of the screen (an expanded
  /// row, a review step). Each step is followed by [settleL10nScreen].
  final Future<void> Function(WidgetTester tester)? reveal;
}

/// Answers the audio plugin's channels, so screens that prepare sounds can
/// let their platform calls finish inside `runAsync`.
void quietAudioForL10nScreens() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in [
    'xyz.luan/audioplayers.global',
    'xyz.luan/audioplayers.global/events',
  ]) {
    messenger.setMockMethodCallHandler(MethodChannel(name), (_) async => null);
  }
  messenger.setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers'),
    (call) async {
      final id = (call.arguments as Map?)?['playerId'];
      if (call.method == 'create' && id is String) {
        messenger.setMockMethodCallHandler(
          MethodChannel('xyz.luan/audioplayers/events/$id'),
          (_) async => null,
        );
      }
      return call.method == 'getCurrentPosition' ? 0 : null;
    },
  );
}

/// The phone the layout tests use: an iPhone SE-sized 375x667 screen.
const l10nPhone = Size(375, 667);

/// Lets mocked network replies arrive and short animations finish.
Future<void> settleL10nScreen(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 600));
}

/// Pumps [screen] in [locale] on [size] at [textScale]. Returns the context
/// so the caller can dispose what the screen needed with
/// [disposeL10nScreen].
Future<L10nScreenContext> pumpL10nScreen(
  WidgetTester tester,
  L10nScreen screen,
  Locale locale, {
  double textScale = 1,
  Size size = l10nPhone,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'trimmy.issuer-terms.v1.${fixtures.account}': [
      jsonEncode(['xstocks', termsVersion]),
    ],
  });
  LiveIssuerTerms.resetSession();
  final preferences = await SharedPreferences.getInstance();
  final context = L10nScreenContext(locale, preferences);
  await tester.pumpWidget(
    localizedTestApp(
      locale: locale,
      textScale: textScale,
      home: screen.build(context),
    ),
  );
  await settleL10nScreen(tester);
  return context;
}

Future<void> disposeL10nScreen(
  WidgetTester tester,
  L10nScreenContext context,
) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  for (final disposer in context._disposers.reversed) {
    disposer();
  }
}

/// The production screens both localization tests pump.
final l10nScreens = <L10nScreen>[
  L10nScreen(
    'onboarding welcome',
    (c) => TrimmyOnboarding(onCompleted: (_) {}, onHaveAccount: () {}),
  ),
  L10nScreen(
    'welcome note',
    (c) => ReviewWelcomeNotePage(onSkip: () {}, onContinue: () {}),
  ),
  L10nScreen(
    'sign-in methods',
    (c) => SignInMethodsPage(
      onClose: () {},
      onEmail: () {},
      onGoogle: () {},
      onX: () {},
      onApple: () {},
      onGuest: () {},
    ),
  ),
  L10nScreen(
    'sign-in methods, busy with a notice and an error',
    (c) => SignInMethodsPage(
      onClose: () {},
      onEmail: () {},
      onGoogle: () {},
      onX: () {},
      title: c.l10n.signInTitleSaveDesk,
      caption: c.l10n.signInCaptionExpired,
      notice: c.l10n.signInNoticeExpired,
      error: c.l10n.signInErrorConnectionExpired,
      busy: true,
    ),
  ),
  L10nScreen(
    'sign-in gate, expired guest',
    (c) => ProductSignInScreen(
      controller: null,
      onLater: () {},
      entryGate: true,
      expiredGuestRecovery: true,
    ),
  ),
  L10nScreen(
    'sign-in gate',
    (c) =>
        ProductSignInScreen(controller: null, onLater: () {}, entryGate: true),
  ),
  L10nScreen(
    'guest desk recovery',
    (c) => GuestDeskRecoveryScreen(onStartNew: () async {}),
    reveal: (tester) async {
      final start = find.byKey(const ValueKey('guest-recovery-start-new'));
      await tester.ensureVisible(start);
      await tester.pump();
      await tester.tap(start);
    },
  ),
  L10nScreen(
    'guest desk preserved',
    (c) => GuestDeskPreservedScreen(onContinue: () {}, expired: true),
  ),
  L10nScreen(
    'fund wallet',
    (c) => Scaffold(body: FundWalletSheet(account: _account(c))),
  ),
  L10nScreen(
    'paper desk',
    (c) => DeskScreen(
      snapshot: DeskSnapshot(
        handle: 'mira',
        paperValue: '10,250.5',
        wallStreetLine: WallStreetClock.label(
          DateTime.utc(2026, 9, 30, 15),
          c.l10n,
        ),
        rank: c.l10n.rankRookie,
        streak: 3,
        trims: 40,
        paperChange: '250.5',
        paperChangePercent: 2.5,
        holdings: const [
          DeskHolding(
            assetId: 'apple',
            variantMint: testMint,
            name: 'Apple',
            symbol: 'AAPLx',
            quantity: '1.25',
            valuePaper: '290.5',
            changePercent: 1.2,
          ),
          DeskHolding(
            assetId: 'nvidia',
            variantMint: xNvidiaMint,
            name: 'NVIDIA',
            symbol: 'NVDAx',
            quantity: '3',
            valuePaper: null,
            changePercent: null,
          ),
        ],
      ),
      onOpenMarket: () {},
      onFastBuy: () {},
      onOpenPortfolio: () {},
      onChoosePersona: () {},
      onSignIn: () {},
    ),
  ),
  L10nScreen('real desk', (c) {
    final account = _account(c);
    return DeskScreen(
      real: true,
      snapshot: DeskSnapshot.newRookie(
        handle: 'mira',
        wallStreetLine: WallStreetClock.label(
          DateTime.utc(2026, 9, 30, 15),
          c.l10n,
        ),
      ),
      realBalance: realUsd(1234.5, c.formats),
      realBalanceLabel: c.l10n.appRealBalanceLabel,
      realBalanceNote: c.l10n.appRealBalanceUsdcAvailable,
      realSolBalance: c.formats.number('0.05'),
      realHoldings: RealHoldings(account: account, onAddMoney: () {}),
      onOpenMarket: () {},
      onFastBuy: () {},
      onAddMoney: () {},
      onSendMoney: () {},
      onOpenPortfolio: () {},
      onSwitchMode: () {},
    );
  }),
  L10nScreen('market', (c) {
    final gateway = FakeMarketSearchGateway();
    final recents = MarketRecentsController();
    c.dispose(gateway.dispose);
    c.dispose(recents.dispose);
    return FoundationMarketPage(
      companies: [
        testCompany(),
        testCompany(assetId: 'nvidia', name: 'NVIDIA', symbol: 'NVDA'),
      ],
      searchGateway: gateway,
      recents: recents,
      onOpenCompany: (_) {},
      onSignIn: () {},
    );
  }),
  L10nScreen(
    'stock page',
    (c) => CompanyStockPage(
      details: MarketStockDetails(company: testCompany()),
      orderRepository: FakePaperOrderRepository(),
      clientOrderId: () => 'l10n-order',
      availablePaper: '1000',
      availableShares: '0.5',
    ),
  ),
  L10nScreen(
    'paper buy',
    (c) => PaperOrderFlow(
      company: testCompany(),
      side: PaperOrderSide.buy,
      repository: FakePaperOrderRepository(),
      clientOrderId: () => 'l10n-order',
      reasonMutationId: () => testReasonMutationId,
      availablePaper: '10000',
      availableShares: '0',
    ),
    reveal: (tester) async {
      await tester.tap(find.byKey(const ValueKey('paper-preset-500')));
      await tester.pump();
      final review = find.byKey(const ValueKey('paper-order-review-button'));
      await tester.ensureVisible(review);
      await tester.pump();
      await tester.tap(review);
    },
  ),
  L10nScreen(
    'first trade',
    (c) => FirstPaperTradePage(
      companies: [testCompany()],
      repository: FakePaperOrderRepository(),
      availablePaper: '10000',
      clientOrderId: () => 'l10n-order',
      onConfirmed: (_) {},
      onFinished: () async {},
      onExit: () async {},
    ),
  ),
  L10nScreen(
    'paper sell',
    (c) => PaperOrderFlow(
      company: testCompany(),
      side: PaperOrderSide.sell,
      repository: FakePaperOrderRepository(),
      clientOrderId: () => 'l10n-order',
      availablePaper: '9950',
      availableShares: '0.132042',
    ),
  ),
  L10nScreen('fast buy', (c) {
    final gateway = FakeMarketSearchGateway();
    c.dispose(gateway.dispose);
    return Scaffold(
      body: FastBuySheet(
        gateway: gateway,
        companies: [testCompany()],
        orderBuilder: (company, back) => const SizedBox(),
      ),
    );
  }),
  L10nScreen(
    'real buy',
    (c) => LiveOrderFlow(
      account: _account(c),
      origin: _origin,
      company: discoveryCompany('nvidia', [(xNvidiaMint, 900000)]),
      httpClient: _tradingClient(),
      onBack: () {},
      onAddMoney: () async {},
    ),
  ),
  L10nScreen(
    'real sell',
    (c) => LiveOrderFlow(
      account: _account(c),
      origin: _origin,
      company: discoveryCompany('nvidia', [(xNvidiaMint, 900000)]),
      initialSell: true,
      httpClient: _tradingClient(),
      onBack: () {},
      onAddMoney: () async {},
    ),
  ),
  L10nScreen(
    'real trade history',
    (c) => LiveTradeHistoryScreen(
      account: _account(c),
      origin: _origin,
      onBack: () {},
      onOpenAsset: (_, _) async {},
      httpClient: MockClient(
        (_) async => _json({
          'schemaVersion': 1,
          'network': 'solana:mainnet-beta',
          'orders': [_trade(1, 'confirmed', true), _trade(2, 'failed', false)],
          'nextCursor': 'older',
        }),
      ),
    ),
    reveal: (tester) =>
        tester.tap(find.byKey(ValueKey('trade-${_tradeId(1)}'))),
  ),
  L10nScreen(
    'send',
    (c) => SendMoneyFlow(
      account: _account(c),
      origin: _origin,
      onBack: () {},
      httpClient: MockClient((_) async => _json({'transfer': null})),
    ),
  ),
  L10nScreen(
    'career floor',
    (c) => FloorScreen(
      signedIn: true,
      onSignIn: () {},
      onOpenMarket: () {},
      career: _career(c),
      missions: _missions,
    ),
  ),
  L10nScreen(
    'career world',
    (c) => Scaffold(
      body: CareerWorld(controller: _workdays(c), onOpen: (_) {}),
    ),
  ),
  L10nScreen(
    'workday',
    (c) => WorkdayScreen(
      controller: _workdays(c),
      assignmentId: _firstAssignment,
      onCompleted: () async {},
    ),
  ),
  L10nScreen(
    'profile',
    (c) => ProfileScreen(
      handle: 'mira',
      persona: c.l10n.personaWolfName,
      personaId: 'wolf',
      signedIn: true,
      onSettings: () {},
      onSignIn: () {},
      onChangePersona: () {},
      career: _career(c),
    ),
  ),
  L10nScreen(
    'settings',
    (c) => ProductSettingsScreen(
      state: _settings(c),
      onNotificationChanged: (_, _) {},
      onSoundChanged: (_) {},
      onHapticsChanged: (_) {},
      onResetPaper: () async => SettingsPaperResetReceipt(
        revision: 2,
        currentRevision: 2,
        paperBalance: '10000',
        resetAt: DateTime.utc(2026, 9, 30),
      ),
      onTerms: () {},
      onPrivacy: () {},
      onHelp: () {},
      onCloseAccount: () {},
    ),
  ),
  L10nScreen(
    'language picker',
    (c) =>
        const Scaffold(body: LanguagePickerSheet(current: AppLanguage.phone)),
  ),
  L10nScreen(
    'reason privacy',
    (c) => const Scaffold(
      body: ReasonPrivacySheet(
        current: ReasonVisibility.friends,
        initial: ReasonVisibility.everyone,
        friendsSharingAvailable: true,
      ),
    ),
  ),
  L10nScreen(
    'reminder choice',
    (c) => ReminderPreferencePage(
      preferences: c.preferences,
      principal: 'l10n',
      onDone: () async {},
      requestPermission: () async => OnboardingNotificationStatus.granted,
      setReminder: (_) async => true,
    ),
  ),
  L10nScreen(
    'terms',
    (c) =>
        const ProductInformationScreen(information: ProductInformation.terms),
  ),
  L10nScreen(
    'tab bar',
    (c) => const ProductShell(
      desk: SizedBox(),
      market: SizedBox(),
      floor: SizedBox(),
      profile: SizedBox(),
    ),
  ),
];

final _origin = Uri.parse('https://trimmy.example');

http.Response _json(Object? value, {int status = 200}) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

http.Client _tradingClient() => MockClient(
  (request) async => request.url.path.endsWith('capabilities')
      ? _json(
          capabilitiesV2Json(
            assets: [
              assetJson(
                assetId: 'nvidia',
                mint: xNvidiaMint,
                symbol: 'NVDAx',
                name: 'NVIDIA',
              ),
            ],
          ),
        )
      : _json({'order': null}),
);

String _tradeId(int value) =>
    '11111111-1111-4111-8111-${value.toString().padLeft(12, '0')}';

Map<String, Object?> _trade(int id, String status, bool buy) => {
  'id': _tradeId(id),
  'wallet': fixtures.wallet,
  'status': status,
  'signature': '2' * 88,
  'createdAt': '2026-09-25T13:00:00.123456Z',
  'updatedAt': '2026-09-25T13:00:10.123456Z',
  'asset': {
    'assetId': 'nvidia',
    'mint': fixtures.nvidiaMint,
    'symbol': 'NVDAx',
    'name': 'NVIDIA',
    'decimals': 8,
  },
  'terms': <String, Object?>{
    'side': buy ? 'buy' : 'sell',
    'inputMint': buy ? liveUsdcMint : fixtures.nvidiaMint,
    'outputMint': buy ? fixtures.nvidiaMint : liveUsdcMint,
    'inputAmountRaw': buy ? '5000000' : '12345678',
    'quotedOutputAmountRaw': buy ? '12345678' : '5000000',
    'minimumOutputAmountRaw': buy ? '12000000' : '4900000',
  },
  'amountUnits': 'raw_token_units',
  'amountsStatus': 'reviewed_quote',
};

class _Reader implements AccountPortfolioReader {
  @override
  String get accountId => fixtures.account;
  @override
  Future<AccountContextSnapshot> readContext() async =>
      AccountContextSnapshot.fromEnvelope(
        fixtures.contextEnvelope(),
        expectedUserId: fixtures.account,
      );
  @override
  Future<AccountHoldingsSnapshot> readHoldings({
    int? minimumObservedSlot,
  }) async => AccountHoldingsSnapshot.fromEnvelope(
    fixtures.holdingsEnvelopeV2(),
    expectedUserId: fixtures.account,
  );
  @override
  void cancelPending() {}
  @override
  void close() {}
}

/// A signed-in account with a wallet holding USDC, SOL, Apple and NVIDIA.
class _Account extends ChangeNotifier implements AccountController {
  _Account(this.portfolio);
  final AccountPortfolioRepository portfolio;
  @override
  String? get accountId => fixtures.account;
  @override
  int get navigationEpoch => 0;
  @override
  AccountPhase get phase => AccountPhase.active;
  @override
  AccountPortfolioRepository get portfolioRepository => portfolio;
  @override
  AccountPortfolioState get portfolioState => portfolio.state;
  @override
  bool get canSetUpWallet => true;
  @override
  Future<PracticeAccessToken> freshAccessToken() async =>
      PracticeAccessToken(accountId: fixtures.account, token: 'l10n-token');
  @override
  Future<void> refreshPortfolio() async {
    await portfolio.refresh();
    notifyListeners();
  }

  @override
  Future<void> refreshPortfolioAfterTrade({int? confirmedSlot}) =>
      refreshPortfolio();
  @override
  Future<WalletSetupOutcome> setUpWallet() async => WalletSetupOutcome.ready;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AccountController _account(L10nScreenContext c) {
  final portfolio = AccountPortfolioRepository(
    reader: _Reader(),
    clock: () => DateTime.parse('2026-09-14T17:28:28Z'),
  );
  final account = _Account(portfolio);
  unawaited(portfolio.refresh().then((_) => account.notifyListeners()));
  c.dispose(portfolio.dispose);
  c.dispose(account.dispose);
  return account;
}

CareerSummary _career(L10nScreenContext c) => CareerSummary(
  revision: 5,
  trims: const CareerTrims(total: 40, today: 10, thisWeek: 30),
  rank: CareerRankProgress(
    id: CareerRank.rookie,
    label: c.l10n.rankRookie,
    paperLimit: '10000',
    threshold: 0,
  ),
  nextRank: CareerNextRank(
    id: CareerRank.analyst,
    label: c.l10n.rankAnalyst,
    threshold: 300,
    trimsRemaining: 260,
    promotionRequired: false,
  ),
  streak: const CareerStreak(
    days: 2,
    status: CareerStreakStatus.active,
    lastActiveDate: '2026-09-20',
  ),
  careerStarted: true,
  firstConfirmedBuy: null,
  serverDate: '2026-09-20',
  updatedAt: DateTime.utc(2026, 9, 20, 12),
);

// Mission titles and instructions are the server's; the screen shows its own
// copy for each mission id.
final _missions = CareerMissionBoard(
  revision: 5,
  currentRank: CareerRank.rookie,
  missions: [
    CareerMission(
      id: CareerMissionId.firstPaperBuy,
      chapterRank: CareerRank.rookie,
      order: 1,
      kind: CareerMissionKind.action,
      title: 'server-title-1',
      instruction: 'server-instruction-1',
      trimsReward: 20,
      promotesToRank: null,
      status: CareerMissionStatus.complete,
      completedAt: DateTime.utc(2026, 9, 20, 9),
    ),
    const CareerMission(
      id: CareerMissionId.writeAReason,
      chapterRank: CareerRank.rookie,
      order: 2,
      kind: CareerMissionKind.action,
      title: 'server-title-2',
      instruction: 'server-instruction-2',
      trimsReward: 20,
      promotesToRank: null,
      status: CareerMissionStatus.ready,
      completedAt: null,
    ),
    const CareerMission(
      id: CareerMissionId.holdThroughRedDay,
      chapterRank: CareerRank.rookie,
      order: 3,
      kind: CareerMissionKind.promotion,
      title: 'server-title-3',
      instruction: 'server-instruction-3',
      trimsReward: 20,
      promotesToRank: CareerRank.analyst,
      status: CareerMissionStatus.locked,
      completedAt: null,
    ),
  ],
);

ProductSettingsState _settings(L10nScreenContext c) => ProductSettingsState(
  account: SettingsAccountState(
    signedIn: true,
    handle: '@mira',
    persona: c.l10n.personaWolfName,
    email: 'mira@example.com',
    signInMethods: const {SettingsSignInMethod.email, SettingsSignInMethod.x},
  ),
  notifications: const {
    SettingsNotificationKind.tradesAndReceipts: SettingsNotificationValue(
      enabled: true,
    ),
  },
  quietHours: SettingsQuietHours(
    enabled: false,
    startLabel: c.formats.time12(DateTime(2000, 1, 1, 22)),
    endLabel: c.formats.time12(DateTime(2000, 1, 1, 7)),
    available: false,
  ),
  appearance: const SettingsAppearanceState(
    soundEnabled: true,
    hapticsEnabled: true,
    animationsEnabled: true,
    systemReduceMotionEnabled: false,
  ),
  paper: const SettingsPaperState(limit: 10000, resetAvailable: true),
  money: const SettingsMoneyState(
    availability: SettingsFeatureAvailability.available,
  ),
  wallet: SettingsWalletState(
    availability: SettingsFeatureAvailability.available,
    address: fixtures.wallet,
  ),
  privacy: const SettingsPrivacyState(
    holdingsVisibility: SettingsVisibility.friends,
  ),
);

/// The intern workdays as the server serves them; their titles and bodies
/// are server content and stay as written.
Map<String, dynamic> _journeyJson() {
  final source =
      jsonDecode(
            File('../../content/workdays/intern-v1.json').readAsStringSync(),
          )
          as Map;
  final assignments = List<Map<String, dynamic>>.from(
    source['assignments'] as List,
  );
  for (final item in assignments) {
    item['step'] = 0;
    item['revision'] = 0;
    item['draft'] = '';
    item['evidence']['count'] =
        (item['evidence']['requiredIds'] as List).length;
    item['file']['count'] = (item['file']['requiredIds'] as List).length;
  }
  return {'assignments': assignments};
}

String get _firstAssignment =>
    ((_journeyJson()['assignments'] as List).first as Map)['id'] as String;

WorkdayController _workdays(L10nScreenContext c) {
  final journey = _journeyJson();
  final controller = WorkdayController(
    WorkdayRepository(
      _origin,
      () async => const GuestPaperAuthorization('l10n'),
      client: MockClient((_) async => _json({'journey': journey})),
    ),
  )..journey = WorkJourney.fromJson(journey);
  c.dispose(controller.dispose);
  return controller;
}
