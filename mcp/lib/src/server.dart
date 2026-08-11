/// The request loop, as a function of a message.
///
/// [McpServer.handle] takes one decoded JSON-RPC object and returns the object
/// to send back, or null for a notification. Nothing here touches stdin or
/// stdout, so the whole protocol is testable without spawning a process.
library;

import 'protocol.dart';
import 'tools.dart';

/// What a client is told this server is for.
///
/// MCP delivers `instructions` to the model once, at initialisation. It is the
/// only place to say the two things no per-tool description can enforce on its
/// own: check the address first, and stop at the payment.
const serverInstructions = '''
Trimmy turns one XRPL payment into a standing rule on Flare. The rule keeps
evaluating after the person closes the conversation, and it pays whoever
executes it a fee it carries itself.

You can compose a rule. You cannot sign one, send one, or move anyone's money.
trimmy_compose_rule returns fields for a human to enter in their own XRPL
wallet. Present them, say plainly that the rule does not exist until they send
the payment, and stop. Do not claim a rule is armed on the strength of having
composed it.

Call trimmy_check_address before composing anything, every time. Flare derives
a personal account from the address STRING and the derivation never fails, so a
single mistyped character produces a valid looking account the person does not
control, and the payment cannot be recalled. The four byte checksum is the only
place that error is detectable, and only before sending.

Never handle a private rule's threshold price. If a person tells you the number
they want a private rule to fire at, do not put it in a tool call, do not repeat
it back, and do not store it. Compose the rule without it and hand them the
provisioning command so the number goes straight from them to the enclave. A
private rule whose threshold passed through this conversation is not private.

A refusal is an answer, not a failure. Do not retry it, work around it, or
proceed anyway. Tell the person what was refused and why.

Everything here runs on Flare Coston2 testnet. Nothing has run on Flare mainnet.
Say so if the person seems to think otherwise.''';

/// A protocol session.
final class McpServer {
  McpServer({required List<TrimmyTool> tools, this.version = '0.1.0'})
      : _tools = {for (final tool in tools) tool.name: tool};

  final Map<String, TrimmyTool> _tools;
  final String version;

  List<TrimmyTool> get tools => _tools.values.toList(growable: false);

  /// Handles one message. Returns null when no response may be sent.
  Future<Map<String, Object?>?> handle(RpcMessage message) async {
    // Notifications get no response, ever. Answering one is the most common way
    // a hand-written server breaks a client that validates strictly.
    if (message.isNotification) return null;

    return switch (message.method) {
      'initialize' => rpcResult(message.id, _initialize(message.params)),
      'ping' => rpcResult(message.id, const {}),
      'tools/list' => rpcResult(message.id, {
          'tools': [
            for (final tool in _tools.values)
              {
                'name': tool.name,
                'title': tool.title,
                'description': tool.description,
                'inputSchema': tool.inputSchema,
                // Declared so a host can reason about this server without
                // trusting prose. Nothing here writes, and nothing destroys.
                'annotations': {
                  'title': tool.title,
                  'readOnlyHint': true,
                  'destructiveHint': false,
                  'idempotentHint': true,
                  'openWorldHint': tool.readsChain,
                },
              },
          ],
        }),
      'tools/call' => await _callTool(message),
      _ => rpcError(message.id, JsonRpcError.methodNotFound, 'unknown method: ${message.method}'),
    };
  }

  Map<String, Object?> _initialize(Map<String, Object?>? params) {
    final proposed = params?['protocolVersion'];
    // Echo a version we know; otherwise answer with ours. Silently accepting an
    // unknown one is worse than a visible mismatch, because the client would
    // then assume features that are not implemented.
    final version = proposed is String && supportedProtocolVersions.contains(proposed)
        ? proposed
        : preferredProtocolVersion;
    return {
      'protocolVersion': version,
      'capabilities': {
        'tools': {'listChanged': false},
      },
      'serverInfo': {'name': 'trimmy', 'version': this.version},
      'instructions': serverInstructions,
    };
  }

  Future<Map<String, Object?>> _callTool(RpcMessage message) async {
    final name = message.params?['name'];
    if (name is! String) {
      return rpcError(message.id, JsonRpcError.invalidParams, 'tools/call needs a name');
    }
    final tool = _tools[name];
    if (tool == null) {
      return rpcError(message.id, JsonRpcError.invalidParams, 'unknown tool: $name');
    }
    final args = message.params?['arguments'];
    try {
      final result = await tool.call(args is Map<String, Object?> ? args : const {});
      return rpcResult(message.id, {
        'content': [
          {'type': 'text', 'text': result.text},
        ],
        if (result.structured != null) 'structuredContent': result.structured,
        'isError': result.isError,
      });
    } catch (e) {
      // A thrown exception really is "could not be answered", so this is the
      // one place isError is honest. A refusal never reaches here: it comes
      // back as a successful ToolResult whose text says no.
      return rpcResult(message.id, {
        'content': [
          {'type': 'text', 'text': '$name could not be answered: $e'},
        ],
        'isError': true,
      });
    }
  }
}
