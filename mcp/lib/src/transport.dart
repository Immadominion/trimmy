/// Newline-delimited JSON-RPC over two pipes.
///
/// MCP's stdio transport is exactly this: one JSON object per line on stdin,
/// one per line on stdout. No length headers, no framing. That is LSP, and
/// confusing the two is the usual first bug.
///
/// ## stdout belongs to the protocol
///
/// Nothing but responses may be written to it. A stray `print`, a package
/// warning, a stack trace, any of them lands mid-stream and the client's
/// parser abandons the session, usually reporting something that looks
/// nothing like the cause. [serve] takes its sinks as parameters so a test can
/// assert exactly what was written, rather than trusting that nobody printed.
library;

import 'dart:async';
import 'dart:convert';

import 'protocol.dart';
import 'server.dart';

/// Runs [server] against a stream of decoded lines.
///
/// Returns when [lines] closes. Malformed input is answered and the session
/// continues: a client that sends one bad frame has not necessarily stopped
/// being a client, and killing the process would lose the ones after it.
Future<void> serve({
  required Stream<String> lines,
  required McpServer server,
  required void Function(String) send,
  void Function(String)? log,
}) async {
  await for (final line in lines) {
    if (line.trim().isEmpty) continue;

    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException catch (e) {
      // No id is recoverable from unparseable input, so the response carries
      // a null one, which is what the specification asks for.
      send(jsonEncode(rpcError(null, JsonRpcError.parseError, e.message)));
      continue;
    }

    final message = RpcMessage.from(decoded);
    if (message == null) {
      final id = decoded is Map<String, Object?> ? decoded['id'] : null;
      send(jsonEncode(rpcError(
        id,
        JsonRpcError.invalidRequest,
        'Not a JSON-RPC request: no "method".',
      )));
      continue;
    }

    try {
      final response = await server.handle(message);
      if (response != null) send(jsonEncode(response));
    } catch (e, stack) {
      // The loop must outlive any single request. A server that dies on one
      // bad call takes the agent's ability to check the *next* payment with
      // it, which is the failure that actually costs money.
      log?.call('$e\n$stack');
      if (!message.isNotification) {
        send(jsonEncode(
          rpcError(message.id, JsonRpcError.internalError, e.toString()),
        ));
      }
    }
  }
}

/// Decodes a byte stream into lines, tolerating CRLF.
Stream<String> jsonRpcLines(Stream<List<int>> input) =>
    input.transform(utf8.decoder).transform(const LineSplitter());
