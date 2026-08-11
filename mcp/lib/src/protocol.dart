/// The MCP wire protocol, as data.
///
/// MCP is JSON-RPC 2.0 over a stream of newline-delimited JSON objects. That is
/// the whole transport, no framing headers, no handshake beyond `initialize`.
/// It is written out here rather than pulled from a package because this
/// process is going to be consulted by something holding a wallet, and a
/// dependency that can be updated underneath us is a worse trade than sixty
/// lines of JSON-RPC.
///
/// ## The one rule that breaks everything if broken
///
/// **stdout carries the protocol and nothing else.** A stray `print`, a
/// warning, a stack trace, any of them lands mid-stream and the client's
/// parser gives up on the session. Every diagnostic in this package goes to
/// stderr. There is a test for it, because "remember not to print" is not a
/// mechanism.
library;

/// JSON-RPC error codes. The negative ones are the specification's; MCP adds no
/// codes of its own and expects tool failures to arrive as *successful*
/// responses carrying `isError`, which is a distinction §3 of `server.dart`
/// depends on.
abstract final class JsonRpcError {
  static const parseError = -32700;
  static const invalidRequest = -32600;
  static const methodNotFound = -32601;
  static const invalidParams = -32602;
  static const internalError = -32603;
}

/// Protocol revisions this server speaks.
///
/// The client proposes one in `initialize`; we echo it back when we know it and
/// otherwise answer with [preferredProtocolVersion]. Silently accepting an
/// unknown version would be worse than a visible mismatch: the client would
/// assume features we do not implement.
const supportedProtocolVersions = <String>{
  '2025-06-18',
  '2025-03-26',
  '2024-11-05',
};

const preferredProtocolVersion = '2025-06-18';

/// A single JSON-RPC message, already parsed.
///
/// `id` absent means a **notification**: the specification forbids a response,
/// and sending one anyway is the most common way a hand-written server breaks a
/// client that is strict about it.
final class RpcMessage {
  const RpcMessage({required this.method, this.id, this.params});

  final String method;
  final Object? id;
  final Map<String, Object?>? params;

  bool get isNotification => id == null;

  /// Parses one decoded JSON object, or returns null if it is not a request.
  static RpcMessage? from(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final method = json['method'];
    if (method is! String) return null;
    final params = json['params'];
    return RpcMessage(
      method: method,
      id: json['id'],
      params: params is Map<String, Object?> ? params : null,
    );
  }
}

Map<String, Object?> rpcResult(Object? id, Map<String, Object?> result) =>
    {'jsonrpc': '2.0', 'id': id, 'result': result};

Map<String, Object?> rpcError(Object? id, int code, String message) =>
    {
      'jsonrpc': '2.0',
      'id': id,
      'error': {'code': code, 'message': message},
    };
