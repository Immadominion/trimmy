import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/product/market/live_trading.dart';
import 'live_trading_test_support.dart';
import 'market_test_support.dart';

Map<String, Object?> capabilities() => {
  'enabled': true,
  'network': 'solana:mainnet-beta',
  'minimumSolBalanceLamports': '5000',
  'assets': [
    {
      'assetId': 'apple',
      'mint': testMint,
      'name': 'Apple',
      'symbol': 'AAPLx',
      'decimals': 8,
      'maxBuyInputRaw': '100000000',
      'maxSellInputRaw': '100000000',
    },
  ],
};
void main() {
  test(
    'exact conversions retain small fractions and reject ambiguous input',
    () {
      expect(liveAmountRaw('0.00591613', 8), '591613');
      expect(liveAmountRaw('9007199254740993', 8), '900719925474099300000000');
      expect(liveAmountRaw('1.000001', 6), '1000001');
      expect(liveAmountRaw('0.0000001', 6), isNull);
      for (final text in ['-1', '0', 'NaN', '1e3', '1,000', '1.2.3']) {
        expect(liveAmountRaw(text, 8), isNull);
      }
      expect(liveDecimal('591613', 8), '0.00591613');
      expect(liveDecimal('100000000', 8), '1');
      expect(liveDecimal('0', 8), '0');
    },
  );
  test('capability must match both company and issuer mint', () {
    final caps = LiveTradingCapabilities.fromJson(capabilities());
    expect(caps.forCompany(testCompany())?.symbol, 'AAPLx');
    expect(caps.forCompany(testCompany(assetId: 'tesla')), isNull);
    expect(caps.forMint(testMint)?.maxBuyInputRaw, '100000000');
  });
  test(
    'invalid capability precision, duplicate mints and other networks fail closed',
    () {
      final raw = capabilities();
      final asset = (raw['assets'] as List).first as Map;
      asset['decimals'] = 19;
      expect(
        () => LiveTradingCapabilities.fromJson(raw),
        throwsFormatException,
      );
      final duplicate = capabilities();
      (duplicate['assets'] as List).add((duplicate['assets'] as List).first);
      expect(
        () => LiveTradingCapabilities.fromJson(duplicate),
        throwsFormatException,
      );
      expect(
        () => LiveTradingCapabilities.fromJson({
          ...capabilities(),
          'network': 'devnet',
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'capability request rejects redirects and distinguishes outage from disabled',
    () async {
      final client = MockClient((request) async {
        expect(request.followRedirects, isFalse);
        return http.Response(
          jsonEncode({...capabilities(), 'enabled': false}),
          200,
        );
      });
      final caps = await fetchLiveTradingCapabilities(
        Uri.parse('https://api.trimmy.test'),
        client: client,
      );
      expect(caps.enabled, isFalse);
      await expectLater(
        fetchLiveTradingCapabilities(
          Uri.parse('https://api.trimmy.test'),
          client: MockClient((_) async => http.Response('', 503)),
        ),
        throwsFormatException,
      );
      await expectLater(
        fetchLiveTradingCapabilities(
          Uri.parse('http://api.trimmy.test'),
          client: client,
        ),
        throwsArgumentError,
      );
    },
  );

  group('issuer-aware capabilities', () {
    test('parse issuers, token precision and issuer fees', () {
      final caps = LiveTradingCapabilities.fromJson(capabilitiesV2Json());
      expect(caps.schemaVersion, 2);
      expect(caps.legacy, isFalse);
      expect(caps.issuers.keys, [
        'xstocks',
        'ondo',
        'backpack',
        'prestocks',
        'tessera',
      ]);
      final ondo = caps.forMint(ondoNvidiaMint)!;
      expect(ondo.assetId, 'nvidia');
      expect(ondo.symbol, 'NVDAon');
      expect(ondo.decimals, 9);
      expect(ondo.transferFeeBps, 0);
      final issuer = caps.issuerFor(ondo);
      expect(issuer.name, 'Ondo');
      expect(issuer.legalName, 'Ondo Limited');
      expect(issuer.productType, 'Tracker certificate');
      expect(
        issuer.holderRights,
        'No voting rights. Dividends are reinvested.',
      );
      expect(issuer.excludedRegions, ['United States']);
      expect(issuer.termsUrl, Uri.parse('https://terms.example/ondo'));
      expect(issuer.attestation.version, termsVersion);
      expect(issuer.attestation.text, 'I accept the Ondo terms.');
      expect(caps.forMint(preStocksMint)!.transferFeeBps, 300);
      expect(caps.forMint(backpackNvidiaMint)!.decimals, 6);
      expect(caps.variantLabel(ondo), 'Ondo · NVDAon');
    });

    test('reject duplicates, unknown issuers and bad values', () {
      Map<String, Object?> mutate(void Function(Map<String, Object?>) change) {
        final value = capabilitiesV2Json();
        change(value);
        return value;
      }

      Map<String, Object?> firstAsset(Map<String, Object?> value) =>
          (value['assets'] as List).first as Map<String, Object?>;
      Map<String, Object?> firstIssuer(Map<String, Object?> value) =>
          (value['issuers'] as List).first as Map<String, Object?>;

      final invalid = <String, Map<String, Object?>>{
        'duplicate issuer': mutate(
          (v) => (v['issuers'] as List).add(issuerJson('ondo')),
        ),
        'unknown issuer': mutate((v) => firstAsset(v)['issuerId'] = 'nobody'),
        'duplicate mint': mutate(
          (v) => (v['assets'] as List).add(
            assetJson(assetId: 'apple', mint: xAppleMint, symbol: 'AAPLx2'),
          ),
        ),
        'fee above 10%': mutate((v) => firstAsset(v)['transferFeeBps'] = 1001),
        'negative fee': mutate((v) => firstAsset(v)['transferFeeBps'] = -1),
        'fractional fee': mutate((v) => firstAsset(v)['transferFeeBps'] = 1.5),
        'text fee': mutate((v) => firstAsset(v)['transferFeeBps'] = '30'),
        'missing fee': mutate((v) => firstAsset(v).remove('transferFeeBps')),
        'missing issuer id': mutate((v) => firstAsset(v).remove('issuerId')),
        'missing sell limit': mutate(
          (v) => firstAsset(v).remove('maxSellInputRaw'),
        ),
        'zero buy limit': mutate((v) => firstAsset(v)['maxBuyInputRaw'] = '0'),
        'usdc as a stock': mutate((v) => firstAsset(v)['mint'] = liveUsdcMint),
        'plain http terms': mutate(
          (v) => firstIssuer(v)['termsUrl'] = 'http://terms.example/x',
        ),
        'terms with credentials': mutate(
          (v) => firstIssuer(v)['termsUrl'] = 'https://a:b@terms.example/x',
        ),
        'missing attestation': mutate(
          (v) => firstIssuer(v).remove('attestation'),
        ),
        'empty attestation text': mutate(
          (v) =>
              (firstIssuer(v)['attestation'] as Map<String, Object?>)['text'] =
                  ' ',
        ),
        'spaced attestation version': mutate(
          (v) =>
              (firstIssuer(v)['attestation']
                      as Map<String, Object?>)['version'] =
                  '2026 09',
        ),
        'region list is not a list': mutate(
          (v) => firstIssuer(v)['excludedRegions'] = 'United States',
        ),
        'control character in a name': mutate(
          (v) => firstIssuer(v)['name'] = 'On\u0000do',
        ),
        'bad issuer id': mutate((v) => firstIssuer(v)['issuerId'] = 'Ondo!'),
        'unknown schema': mutate((v) => v['schemaVersion'] = 3),
        'schema without issuers': mutate((v) => v.remove('issuers')),
        'issuers without schema': mutate((v) => v.remove('schemaVersion')),
        'too many assets': mutate(
          (v) => v['assets'] = [
            for (var i = 0; i <= liveCapabilitiesMaxAssets; i++)
              assetJson(assetId: 'a$i', mint: fakeMint(i), symbol: 'A$i'),
          ],
        ),
      };
      for (final entry in invalid.entries) {
        expect(
          () => LiveTradingCapabilities.fromJson(entry.value),
          throwsFormatException,
          reason: entry.key,
        );
      }
    });

    test('accept an unused issuer and an empty region list', () {
      final value = capabilitiesV2Json(
        issuers: [
          issuerJson('xstocks', name: 'xStocks', excluded: const []),
          issuerJson('ondo', name: 'Ondo'),
          issuerJson('backpack', name: 'Backpack'),
          issuerJson('prestocks', name: 'PreStocks'),
          issuerJson('tessera', name: 'Tessera'),
        ],
      );
      final caps = LiveTradingCapabilities.fromJson(value);
      expect(caps.issuers['tessera']?.name, 'Tessera');
      expect(caps.issuers['xstocks']?.excludedRegions, isEmpty);
    });

    test('a legacy server keeps xStocks with the Backed terms', () {
      final caps = LiveTradingCapabilities.fromJson(capabilities());
      expect(caps.schemaVersion, 1);
      expect(caps.legacy, isTrue);
      final asset = caps.forMint(testMint)!;
      expect(asset.issuerId, 'xstocks');
      expect(asset.transferFeeBps, 0);
      final issuer = caps.issuerFor(asset);
      expect(issuer.name, 'xStocks');
      expect(
        issuer.termsUrl,
        Uri.parse('https://assets.backed.fi/legal-documentation'),
      );
      expect(issuer.attestation.text, 'I’m eligible under the issuer’s terms.');
      // Deployed legacy capabilities predate per-asset limits and names.
      final bare = capabilities();
      final row = (bare['assets'] as List).first as Map;
      row
        ..remove('maxBuyInputRaw')
        ..remove('maxSellInputRaw')
        ..remove('name');
      final old = LiveTradingCapabilities.fromJson(bare).forMint(testMint)!;
      expect(old.maxBuyInputRaw, '100000000');
      expect(old.name, 'AAPLx');
    });

    test('variants are the company’s listed tokens, most liquid first', () {
      final caps = LiveTradingCapabilities.fromJson(capabilitiesV2Json());
      final nvidia = discoveryCompany('nvidia', [
        (xNvidiaMint, 50000),
        (backpackNvidiaMint, null),
        (ondoNvidiaMint, 900000),
      ]);
      expect(caps.variantsFor(nvidia).map((a) => a.symbol), [
        'NVDAon',
        'NVDAx',
        'NVDAbp',
      ]);
      expect(caps.forCompany(nvidia)?.symbol, 'NVDAon');
      expect(caps.tradeable(nvidia), isTrue);

      // A token discovery does not list for this company is never offered.
      final partial = discoveryCompany('nvidia', [(xNvidiaMint, 10)]);
      expect(caps.variantsFor(partial).map((a) => a.symbol), ['NVDAx']);

      // Same mint under another company is not this company's token.
      final impostor = discoveryCompany('tesla', [(ondoNvidiaMint, 10)]);
      expect(caps.variantsFor(impostor), isEmpty);
      expect(caps.forCompany(impostor), isNull);
      expect(caps.tradeable(impostor), isFalse);

      // Equal or missing liquidity keeps the server's order.
      final ties = discoveryCompany('nvidia', [
        (ondoNvidiaMint, null),
        (backpackNvidiaMint, 7),
        (xNvidiaMint, 7),
      ]);
      expect(caps.variantsFor(ties).map((a) => a.symbol), [
        'NVDAx',
        'NVDAbp',
        'NVDAon',
      ]);

      final paused = LiveTradingCapabilities.fromJson(
        capabilitiesV2Json(enabled: false),
      );
      expect(paused.variantsFor(nvidia), hasLength(3));
      expect(paused.tradeable(nvidia), isFalse);
    });

    test(
      'requests schema 3, falling back to 2 and then legacy when older servers say 400',
      () async {
        final urls = <Uri>[];
        final caps = await fetchLiveTradingCapabilities(
          Uri.parse('https://api.trimmy.test'),
          client: MockClient((request) async {
            urls.add(request.url);
            expect(request.followRedirects, isFalse);
            return request.url.queryParameters.containsKey('schema')
                ? http.Response(jsonEncode({'code': 'INVALID_REQUEST'}), 400)
                : http.Response(jsonEncode(capabilities()), 200);
          }),
        );
        expect(urls.map((url) => url.toString()), [
          'https://api.trimmy.test/v1/trading/capabilities?schema=3',
          'https://api.trimmy.test/v1/trading/capabilities?schema=2',
          'https://api.trimmy.test/v1/trading/capabilities',
        ]);
        expect(caps.legacy, isTrue);

        urls.clear();
        final current = await fetchLiveTradingCapabilities(
          Uri.parse('https://api.trimmy.test'),
          client: MockClient((request) async {
            urls.add(request.url);
            return http.Response(jsonEncode(capabilitiesV2Json()), 200);
          }),
        );
        expect(urls, hasLength(1));
        expect(current.legacy, isFalse);

        await expectLater(
          fetchLiveTradingCapabilities(
            Uri.parse('https://api.trimmy.test'),
            client: MockClient((_) async => http.Response('{}', 400)),
          ),
          throwsFormatException,
        );
      },
    );

    test(
      'a full catalog fits and anything past the byte bound is refused',
      () async {
        final full = capabilitiesV2Json(
          assets: [
            for (var i = 0; i < 3000; i++)
              assetJson(
                assetId: 'company-$i',
                mint: fakeMint(i),
                symbol: 'C$i',
                name: 'Company $i Tokenized Stock',
              ),
          ],
        );
        final body = jsonEncode(full);
        expect(utf8.encode(body).length, greaterThan(65536));
        final caps = await fetchLiveTradingCapabilities(
          Uri.parse('https://api.trimmy.test'),
          client: MockClient((_) async => http.Response(body, 200)),
        );
        expect(caps.assets, hasLength(3000));
        await expectLater(
          fetchLiveTradingCapabilities(
            Uri.parse('https://api.trimmy.test'),
            client: MockClient(
              (_) async => http.Response(
                jsonEncode({
                  ...full,
                  'padding': 'x' * liveCapabilitiesMaxBytes,
                }),
                200,
              ),
            ),
          ),
          throwsFormatException,
        );
      },
    );
  });

  group('offered issuers and unavailable tokens', () {
    test('warnings and offers are read, and older servers get defaults', () {
      final caps = LiveTradingCapabilities.fromJson(
        capabilitiesV2Json(
          issuers: [
            issuerJson(
              'xstocks',
              name: 'xStocks',
              warning: 'Not suitable for every investor.\nRead the terms.',
            ),
            issuerJson('ondo', name: 'Ondo'),
            issuerJson('backpack', name: 'Backpack'),
            issuerJson(
              'prestocks',
              name: 'PreStocks',
              offered: false,
              notOfferedReason: 'PreStocks is not offered in Trimmy yet.',
            ),
          ],
        ),
      );
      final xstocks = caps.issuers['xstocks']!;
      expect(
        xstocks.warning,
        'Not suitable for every investor.\nRead the terms.',
      );
      expect(xstocks.offered, isTrue);
      expect(caps.issuers['ondo']!.warning, isEmpty);
      final prestocks = caps.issuers['prestocks']!;
      expect(prestocks.offered, isFalse);
      expect(
        prestocks.notOfferedReason,
        'PreStocks is not offered in Trimmy yet.',
      );

      // An issuer-aware server from before these fields: no warning, and an
      // issuer is offered when it has tokens to trade.
      final older = capabilitiesV2Json();
      for (final issuer in older['issuers'] as List) {
        (issuer as Map)
          ..remove('warning')
          ..remove('offered')
          ..remove('notOfferedReason');
      }
      final defaults = LiveTradingCapabilities.fromJson(older);
      expect(defaults.issuers['ondo']!.offered, isTrue);
      expect(defaults.issuers['ondo']!.warning, isEmpty);
      expect(defaults.issuers['tessera']!.offered, isFalse);
      expect(defaults.unavailable, isEmpty);
    });

    test('a token of an issuer that is not offered never trades', () {
      final caps = LiveTradingCapabilities.fromJson(
        capabilitiesV2Json(
          issuers: [
            issuerJson('xstocks', name: 'xStocks'),
            issuerJson('ondo', name: 'Ondo', offered: false),
            issuerJson('backpack', name: 'Backpack'),
            issuerJson('prestocks', name: 'PreStocks'),
          ],
        ),
      );
      final nvidia = discoveryCompany('nvidia', [
        (ondoNvidiaMint, 900000),
        (xNvidiaMint, 10),
      ]);
      expect(caps.variantsFor(nvidia).map((a) => a.symbol), ['NVDAx']);
      expect(
        caps.tradeableAssets.map((a) => a.symbol),
        isNot(contains('NVDAon')),
      );
      expect(
        caps.reasonFor(ondoNvidiaMint),
        'Ondo tokens are not offered in Trimmy yet.',
      );
    });

    test('unavailable tokens get short plain reasons', () {
      String unknownMint(int index) => fakeMint(index);
      final caps = LiveTradingCapabilities.fromJson(
        capabilitiesV2Json(
          unavailable: [
            {
              'mint': unknownMint(1),
              'issuerId': 'tessera',
              'reason': 'issuer_not_offered',
            },
            {
              'mint': unknownMint(2),
              'issuerId': null,
              'reason': 'identity_unverified',
            },
            {
              'mint': unknownMint(3),
              'issuerId': 'xstocks',
              'reason': 'token_restricted',
            },
            {
              'mint': unknownMint(4),
              'issuerId': 'xstocks',
              'reason': 'low_liquidity',
            },
            {
              'mint': unknownMint(5),
              'issuerId': 'xstocks',
              'reason': 'no_reviewed_route',
            },
            {
              'mint': unknownMint(6),
              'issuerId': 'xstocks',
              'reason': 'price_off_market',
            },
            {
              'mint': unknownMint(7),
              'issuerId': 'xstocks',
              'reason': 'held_back',
            },
            {
              'mint': unknownMint(8),
              'issuerId': 'xstocks',
              'reason': 'not_reviewed',
            },
            {
              'mint': unknownMint(9),
              'issuerId': 'xstocks',
              'reason': 'moon_phase',
            },
            {
              'mint': unknownMint(13),
              'issuerId': 'ondo',
              'reason': 'market_closed',
            },
            {
              'mint': unknownMint(14),
              'issuerId': 'xstocks',
              'reason': 'no_market_maker_quote',
            },
            {
              'mint': unknownMint(10),
              'issuerId': 'nobody',
              'reason': 'issuer_not_offered',
            },
            // Malformed rows are skipped, never fatal.
            {'mint': 'not a mint', 'issuerId': null, 'reason': 'held_back'},
            {'mint': unknownMint(11), 'issuerId': 7, 'reason': 'held_back'},
            {'mint': unknownMint(12), 'issuerId': null, 'reason': null},
            'not an object',
          ],
        ),
      );
      expect(
        caps.reasonFor(unknownMint(1)),
        'Tessera tokens are not offered in Trimmy yet.',
      );
      expect(
        caps.reasonFor(unknownMint(2)),
        'Trimmy could not confirm who issued this token.',
      );
      expect(
        caps.reasonFor(unknownMint(13)),
        'Trades only while US markets are open.',
      );
      expect(
        caps.reasonFor(unknownMint(14)),
        'No market maker is quoting it right now.',
      );
      expect(
        caps.reasonFor(unknownMint(3)),
        'The issuer has restrictions on this token that Trimmy cannot accept.',
      );
      expect(
        caps.reasonFor(unknownMint(4)),
        'Too little trading to buy and sell it safely.',
      );
      expect(
        caps.reasonFor(unknownMint(5)),
        'No order route passed Trimmy’s safety checks.',
      );
      expect(
        caps.reasonFor(unknownMint(6)),
        'Its price is too far from the real share price.',
      );
      expect(
        caps.reasonFor(unknownMint(7)),
        'Paused while Trimmy checks this token.',
      );
      expect(caps.reasonFor(unknownMint(8)), 'Not checked yet.');
      expect(
        caps.reasonFor(unknownMint(9)),
        'Not available to trade in Trimmy.',
      );
      expect(
        caps.reasonFor(unknownMint(10)),
        'This issuer is not offered in Trimmy.',
      );
      expect(caps.unavailable.keys, hasLength(12));
      expect(
        caps.reasonFor(unknownMint(40)),
        'Not available to trade in Trimmy yet.',
      );

      expect(
        () => LiveTradingCapabilities.fromJson(
          capabilitiesV2Json(
            unavailable: [
              for (var i = 0; i <= liveCapabilitiesMaxUnavailable; i++)
                {
                  'mint': fakeMint(i),
                  'issuerId': null,
                  'reason': 'not_reviewed',
                },
            ],
          ),
        ),
        throwsFormatException,
      );
      final unlisted = capabilitiesV2Json()..['unavailable'] = 'none';
      expect(
        () => LiveTradingCapabilities.fromJson(unlisted),
        throwsFormatException,
      );
    });

    test('every variant is listed, tradeable first, the rest with why', () {
      final caps = LiveTradingCapabilities.fromJson(
        capabilitiesV2Json(
          issuers: [
            issuerJson('xstocks', name: 'xStocks'),
            issuerJson('ondo', name: 'Ondo', offered: false),
            issuerJson('backpack', name: 'Backpack'),
            issuerJson('prestocks', name: 'PreStocks'),
            issuerJson('tessera', name: 'Tessera', offered: false),
          ],
          unavailable: [
            {
              'mint': preStocksMint,
              'issuerId': 'tessera',
              'reason': 'issuer_not_offered',
            },
          ],
          assets: [
            assetJson(assetId: 'nvidia', mint: xNvidiaMint, symbol: 'NVDAx'),
            assetJson(
              assetId: 'nvidia',
              mint: ondoNvidiaMint,
              symbol: 'NVDAon',
              issuerId: 'ondo',
              decimals: 9,
            ),
            assetJson(
              assetId: 'nvidia',
              mint: backpackNvidiaMint,
              symbol: 'NVDAbp',
              issuerId: 'backpack',
              decimals: 6,
            ),
          ],
        ),
      );
      final nvidia = discoveryCompany('nvidia', [
        (preStocksMint, 5000000),
        (ondoNvidiaMint, 900000),
        (xAppleMint, null),
        (backpackNvidiaMint, 20),
        (xNvidiaMint, 10),
      ]);
      final options = caps.optionsFor(nvidia);
      expect(options.map((o) => o.label), [
        'Backpack · NVDAbp',
        'xStocks · NVDAx',
        'Tessera · NVDA-mSo',
        'Ondo · NVDAon',
        'Issuer · NVDA-Xsb',
      ]);
      expect(options.map((o) => o.tradeable), [
        true,
        true,
        false,
        false,
        false,
      ]);
      expect(
        options[2].reason,
        'Tessera tokens are not offered in Trimmy yet.',
      );
      expect(options[3].reason, 'Ondo tokens are not offered in Trimmy yet.');
      expect(options[4].reason, 'Not available to trade in Trimmy yet.');
      expect(options.first.asset?.decimals, 6);
    });

    test('at most sixteen issuers', () {
      expect(
        () => LiveTradingCapabilities.fromJson(
          capabilitiesV2Json(
            issuers: [
              issuerJson('xstocks', name: 'xStocks'),
              issuerJson('ondo', name: 'Ondo'),
              issuerJson('backpack', name: 'Backpack'),
              issuerJson('prestocks', name: 'PreStocks'),
              for (var i = 0; i < 13; i++) issuerJson('extra-$i'),
            ],
          ),
        ),
        throwsFormatException,
      );
    });
  });

  group('market states', () {
    final now = DateTime(2026, 9, 27, 15, 40);
    test(
      'each token says when it trades, and an unreadable state never closes one',
      () {
        final caps = LiveTradingCapabilities.fromJson(
          capabilitiesV2Json(
            assets: [
              {
                ...assetJson(
                  assetId: 'apple',
                  mint: fakeMint(1),
                  symbol: 'AAPLx',
                ),
                'market': {'hours': 'always', 'status': 'open'},
              },
              {
                ...assetJson(
                  assetId: 'meta',
                  mint: fakeMint(2),
                  symbol: 'METAon',
                  issuerId: 'ondo',
                  decimals: 9,
                ),
                'minBuyInputRaw': '2000000',
                'market': {
                  'hours': 'us_sessions',
                  'sessions': [
                    'overnight',
                    'premarket',
                    'regular',
                    'postmarket',
                  ],
                  'status': 'closed',
                  'reason': 'outside_sessions',
                  'nextOpenAt': DateTime(
                    2026,
                    9,
                    27,
                    20,
                    5,
                  ).toUtc().toIso8601String(),
                },
              },
              {
                ...assetJson(
                  assetId: 'ibm',
                  mint: fakeMint(3),
                  symbol: 'IBM',
                  issuerId: 'backpack',
                ),
                'market': {
                  'hours': 'always',
                  'status': 'paused',
                  'reason': 'issuer_paused',
                },
              },
              {
                ...assetJson(
                  assetId: 'tesla',
                  mint: fakeMint(4),
                  symbol: 'TSLAx',
                ),
                'market': {'status': 'sleeping'},
                'minBuyInputRaw': 'lots',
              },
            ],
          ),
        );
        final apple = caps.forMint(fakeMint(1))!;
        final meta = caps.forMint(fakeMint(2))!;
        final ibm = caps.forMint(fakeMint(3))!;
        final tesla = caps.forMint(fakeMint(4))!;
        expect(apple.market!.label(now), 'Open 24/7');
        expect(apple.minBuyInputRaw, '1');
        expect(meta.marketOpen, isFalse);
        expect(meta.minBuyInputRaw, '2000000');
        expect(meta.market!.label(now), 'Closed · opens 8:05 PM');
        expect(
          meta.market!.hours(),
          'Trades 24 hours a day, Sunday evening to Friday evening (US Eastern).',
        );
        expect(ibm.market!.label(now), 'Paused by the issuer');
        expect(ibm.marketOpen, isFalse);
        expect(tesla.market, isNull);
        expect(tesla.marketOpen, isTrue);
        expect(tesla.minBuyInputRaw, '1');
      },
    );

    test('a token refused for a closed market says when it opens', () {
      final opens = DateTime.now().add(const Duration(days: 1));
      final caps = LiveTradingCapabilities.fromJson(
        capabilitiesV2Json(
          unavailable: [
            {
              'mint': fakeMint(21),
              'issuerId': 'ondo',
              'reason': 'market_closed',
              'symbol': 'ABNBon',
              'market': {
                'status': 'closed',
                'nextOpenAt': opens.toUtc().toIso8601String(),
              },
            },
            {
              'mint': fakeMint(22),
              'issuerId': 'ondo',
              'reason': 'awaiting_review',
            },
          ],
        ),
      );
      expect(
        caps.reasonFor(fakeMint(21)),
        startsWith('Its market is closed. It opens tomorrow '),
      );
      expect(
        caps.reasonFor(fakeMint(22)),
        'Its market is open. Trimmy is checking it before you can trade.',
      );
    });

    test('times read as today, tomorrow, a weekday or a date', () {
      expect(liveMarketTime(DateTime(2026, 9, 27, 9, 31), now), '9:31 AM');
      expect(
        liveMarketTime(DateTime(2026, 9, 28, 0, 5), now),
        'tomorrow 12:05 AM',
      );
      expect(liveMarketTime(DateTime(2026, 9, 30, 13, 0), now), 'Wed 1:00 PM');
      expect(
        liveMarketTime(DateTime(2026, 10, 12, 21, 30), now),
        'Oct 12, 9:30 PM',
      );
      const always = [
        'overnight',
        'premarket',
        'regular',
        'postmarket',
        'offhours',
      ];
      expect(
        const LiveMarketState(
          status: 'open',
          usSessions: true,
          sessions: always,
        ).label(now),
        'Open now, including weekends',
      );
      expect(
        const LiveMarketState(
          status: 'open',
          usSessions: true,
          sessions: ['regular'],
        ).hours(),
        'Trades during US market hours only, 9:30 AM to 4 PM Eastern on weekdays.',
      );
      expect(
        LiveMarketState(
          status: 'paused',
          reason: 'session_break',
          nextOpenAt: DateTime(2026, 9, 27, 16, 1),
        ).label(now),
        'Short pause · resumes 4:01 PM',
      );
    });
  });

  group('shares', () {
    test('plain shares are raw over 10^decimals for 6 and 9 decimals', () {
      final backpack = LiveShareScale.plain(6);
      expect(backpack.scaled, isFalse);
      expect(backpack.shares('2500000'), '2.5');
      expect(backpack.label('1234567890000'), '1,234,567.89');
      expect(backpack.raw('2.5'), '2500000');
      expect(backpack.raw('0.0000001'), isNull);

      final ondo = LiveShareScale.plain(9);
      expect(ondo.shares('295100000'), '0.2951');
      expect(ondo.raw('0.2951'), '295100000');
      expect(ondo.raw('0'), isNull);
      expect(ondo.raw('abc'), isNull);
    });

    test('the wallet multiplier converts both ways', () {
      // 1 token shows as 1.5 shares.
      final scaled = LiveShareScale.fromDisplay(
        decimals: 9,
        amountRaw: '1000000000',
        displayAmount: '1.5',
      );
      expect(scaled.scaled, isTrue);
      expect(scaled.shares('1000000000'), '1.5');
      expect(scaled.shares('200000000'), '0.3');
      expect(scaled.raw('0.3'), '200000000');
      expect(scaled.raw('1.5'), '1000000000');
      // 1 share is 0.6666666666... tokens: the nearest raw unit is sent.
      expect(scaled.raw('1'), '666666667');
      expect(scaled.label('3000000000000'), '4,500');

      // The same multiplier derived at 8 decimals, as on xStocks.
      final xstocks = LiveShareScale.fromDisplay(
        decimals: 8,
        amountRaw: '123456789',
        displayAmount: '2.46913578',
      );
      expect(xstocks.shares('100000000'), '2');
      expect(xstocks.raw('0.5'), '25000000');
    });

    test('the reviewed multiplier is used as sent, or not at all', () {
      final five = LiveShareScale.fromMultiplier(9, '5');
      expect(five.scaled, isTrue);
      expect(five.approx('29510000'), '0.14755');
      expect(five.label('29000000'), '0.145');
      for (final bad in [null, 5, '', 'abc', '0', '0.0', '-1', '1e3', '1.']) {
        final scale = LiveShareScale.fromMultiplier(9, bad);
        expect(scale.scaled, isFalse, reason: '$bad');
        expect(scale.approx('29510000'), '0.02951', reason: '$bad');
      }
    });

    test('share figures show six places, rounding only where honest', () {
      final plain = LiveShareScale.plain(8);
      expect(plain.label('12345678'), '0.123456');
      expect(plain.approx('12345678'), '0.123457');
      expect(plain.shares('12345678'), '0.123456');
      // Dust too small for six places keeps its full precision.
      expect(plain.label('1'), '0.00000001');
      expect(plain.label('0'), '0');

      // A truncated wallet multiplier and the server's exact one still read
      // a typed amount back unchanged.
      final wallet = LiveShareScale.fromDisplay(
        decimals: 9,
        amountRaw: '1000000000',
        displayAmount: '1.000918075',
      );
      final review = LiveShareScale.fromMultiplier(9, '1.0009180758490996');
      for (final typed in ['1', '0.5', '0.3', '2.25']) {
        expect(review.approx(wallet.raw(typed)!), typed);
      }
    });

    test('an unknown or unusable display amount means plain units', () {
      for (final display in [null, '', '0', '-1', '1e3', 'abc']) {
        final scale = LiveShareScale.fromDisplay(
          decimals: 9,
          amountRaw: '1000000000',
          displayAmount: display,
        );
        expect(scale.scaled, isFalse, reason: '$display');
        expect(scale.shares('1000000000'), '1');
      }
      final zeroRaw = LiveShareScale.fromDisplay(
        decimals: 6,
        amountRaw: '0',
        displayAmount: '4',
      );
      expect(zeroRaw.scaled, isFalse);
    });

    test('grouping and percentages stay short and exact', () {
      expect(liveGroupedDecimal('1234567.8900'), '1,234,567.89');
      expect(liveGroupedDecimal('90071992.54741000'), '90,071,992.54741');
      expect(liveGroupedDecimal('0.5'), '0.5');
      expect(liveGroupedDecimal('007'), '7');
      expect(liveGroupedDecimal('not a number'), 'not a number');
      expect(livePercent(300), '3%');
      expect(livePercent(20), '0.2%');
      expect(livePercent(25), '0.25%');
      expect(livePercent(5), '0.05%');
      expect(livePercent(0), '0%');
      expect(livePercent(1000), '10%');
    });
  });
}
