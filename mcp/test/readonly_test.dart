/// The two guarantees that make this server safe to hand an agent.
///
/// **One: it cannot spend.** No tool signs, holds a key, broadcasts, or moves
/// funds. The worst outcome of wiring Trimmy into an autonomous agent is that a
/// payment does not get composed.
///
/// **Two: it cannot learn a private rule's threshold.** `trimmy_compose_rule`
/// refuses a threshold for a private rule rather than accepting it and
/// promising not to look. That refusal is the difference between "the agent
/// never learns your price" being a property and being a slogan.
///
/// Both claims appear in the server instructions, in the tool descriptions, in
/// the docs and on the website, which is exactly why they need a mechanism
/// instead of five copies of a sentence. This file is the mechanism.
///
/// It is a boundary check, not a proof. It cannot stop someone determined to
/// defeat it. It makes the failure that actually happens, a tool added later
/// that "just sends it too, for convenience", impossible to merge quietly.
library;

import 'dart:io';

import 'package:flare_network/flare_network.dart';
import 'package:trimmy_mcp/trimmy_mcp.dart';
import 'package:test/test.dart';

/// The complete tool set. Adding a name here is a deliberate decision, and any
/// tool not on this list fails the test whether or not it is read-only.
const declaredTools = {
  'trimmy_check_address',
  'trimmy_list_rules',
  'trimmy_describe_rule',
  'trimmy_compose_rule',
};

/// Ways this package could stop being unable to spend.
///
/// `flare_network` exposes no signing API at all, so a signature always comes
/// from somewhere else. But `sendRawTransaction` will broadcast a blob somebody
/// hands it, and `Platform.environment`, `File` and `Process` are three quiet
/// routes to a key. Those are the realistic ones, so those are what is checked.
final forbiddenApis = <String, RegExp>{
  'sendRawTransaction': RegExp(r'\bsendRawTransaction\s*\('),
  'eth_sendRawTransaction': RegExp('eth_sendRawTransaction'),
  'eth_sendTransaction': RegExp('eth_sendTransaction'),
  'eth_sign': RegExp('eth_sign'),
  'signTransaction': RegExp(r'\bsignTransaction\b'),
  'a private key': RegExp(r'\bprivateKey\b', caseSensitive: false),
  'a seed': RegExp(r'\bmnemonic\b|\bwalletSeed\b'),
  'the process environment': RegExp(r'\bPlatform\.environment\b'),
  'the filesystem': RegExp(r'\bFile\s*\('),
  'a subprocess': RegExp(r'\bProcess\.(run|start|runSync)\b'),
};

/// A client factory that fails if it is ever called.
FlareClient _noNetwork() =>
    throw StateError('this tool must answer without reading the chain');

void main() {
  group('it cannot spend', () {
    test('the tool set is exactly the declared one', () {
      final names = trimmyTools(clientFactory: () => FlareClient(FlareChain.coston2))
          .map((t) => t.name)
          .toSet();
      expect(names, equals(declaredTools),
          reason: 'A tool was added or renamed without updating this list. '
              'That is the decision this test exists to make visible.');
    });

    test('no tool is named like it writes', () {
      for (final name in declaredTools) {
        expect(name, isNot(matches(RegExp(r'sign|send|submit|broadcast|transfer|approve|sweep'))),
            reason: '$name reads like a tool that acts.');
      }
    });

    test('every tool declares itself read-only to the host', () async {
      final server = McpServer(
        tools: trimmyTools(clientFactory: () => FlareClient(FlareChain.coston2)),
      );
      final reply = await server.handle(
        const RpcMessage(method: 'tools/list', id: 1),
      );
      final tools = (reply!['result']! as Map)['tools']! as List;
      expect(tools, hasLength(declaredTools.length));
      for (final t in tools.cast<Map<String, Object?>>()) {
        final a = t['annotations']! as Map<String, Object?>;
        expect(a['readOnlyHint'], isTrue, reason: '${t['name']} is not marked read-only');
        expect(a['destructiveHint'], isFalse, reason: '${t['name']} is marked destructive');
      }
    });

    test('the package contains none of the forbidden routes to spending', () {
      final sources = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..add(File('bin/trimmy_mcp.dart'));
      expect(sources, isNotEmpty, reason: 'found no sources to check');

      for (final file in sources) {
        // Strip comments first. This file names every forbidden API in prose,
        // and so does tools.dart when it explains why they are absent.
        final code = file
            .readAsStringSync()
            .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '')
            .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
        for (final entry in forbiddenApis.entries) {
          expect(entry.value.hasMatch(code), isFalse,
              reason: '${file.path} reaches for ${entry.key}. '
                  'If that is deliberate, this server is no longer safe to hand an agent.');
        }
      }
    });
  });

  group('it cannot learn a private threshold', () {
    test('compose refuses a threshold for a private rule, without touching the chain', () async {
      // The factory throws, so this proves the refusal happens BEFORE any
      // network work: the number is rejected, not processed and then discarded.
      final tool = ComposeRuleTool(_noNetwork, defaultTrimmy);
      final result = await tool.call({
        'xrplAddress': 'rDE4JUm2jaue31VwidRXWuWzf5dQkUxcsB',
        'action': 'sell',
        'trigger': 'private',
        'amountEachTime': '1',
        'runs': 1,
        'triggerValue': '150',
      });
      expect(result.isError, isFalse, reason: 'a refusal is an answer, not a failure');
      expect(result.structured!['composed'], isFalse);
      expect(result.structured!['reason'], 'threshold_must_not_reach_the_agent');
      expect(result.text, contains('REFUSED'));
    });

    test('a bad address is refused before the chain is read', () async {
      final tool = ComposeRuleTool(_noNetwork, defaultTrimmy);
      // One character changed from a real address.
      final result = await tool.call({
        'xrplAddress': 'rDE4JUm2jaue31VwidRXWuWzf5dQkUxcsA',
        'action': 'sell',
        'trigger': 'schedule',
        'amountEachTime': '1',
        'runs': 1,
        'triggerValue': '3600',
      });
      expect(result.structured!['composed'], isFalse);
      expect(result.structured!['reason'], 'address_checksum');
    });
  });

  group('the address check needs no network', () {
    test('it validates and refuses entirely offline', () async {
      final tool = CheckAddressTool();
      expect(tool.readsChain, isFalse);

      final good = await tool.call({'address': 'rDE4JUm2jaue31VwidRXWuWzf5dQkUxcsB'});
      expect(good.structured!['valid'], isTrue);

      final bad = await tool.call({'address': 'rDE4JUm2jaue31VwidRXWuWzf5dQkUxcsA'});
      expect(bad.structured!['valid'], isFalse);
      expect(bad.isError, isFalse, reason: 'a mistyped address is an answer, not a tool failure');
      expect(bad.text, contains('DO NOT USE'));
    });
  });
}
