/// An MCP server for Trimmy.
///
/// The claim this package exists to make true: **an agent can compose a mandate
/// over someone's XRP without being able to spend it, and without learning the
/// price they chose.**
///
/// See `src/tools.dart` for how both halves of that are enforced, and
/// `test/readonly_test.dart` for the mechanism that keeps them enforced.
library;

export 'src/protocol.dart';
export 'src/server.dart';
export 'src/tools.dart';
export 'src/transport.dart';
