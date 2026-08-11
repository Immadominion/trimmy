/// `trimmy-mcp`, the server, over stdio.
///
///     {"mcpServers": {"trimmy": {"command": "trimmy-mcp"}}}
///
/// Reads newline-delimited JSON-RPC on stdin and writes it on stdout. Every
/// diagnostic goes to **stderr**, because stdout is the protocol and one stray
/// line ends the session.
library;

import 'dart:io';

import 'package:flare_network/flare_network.dart';
import 'package:trimmy_mcp/trimmy_mcp.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    stdout.writeln(_usage);
    return;
  }

  final server = McpServer(
    // A factory, not a client: a tool that reads nothing must never cause a
    // connection to exist. Each call opens and closes its own, so an idle
    // server holds no socket.
    tools: trimmyTools(clientFactory: () => FlareClient(FlareChain.coston2)),
  );

  await serve(
    lines: jsonRpcLines(stdin),
    server: server,
    send: stdout.writeln,
    log: stderr.writeln,
  );
}

const _usage = '''
trimmy-mcp, let an agent compose a rule over someone's XRP that it cannot spend.

An MCP server over stdio. Add it to an MCP client's configuration:

  {"mcpServers": {"trimmy": {"command": "trimmy-mcp"}}}

Tools
  trimmy_check_address   verify an XRPL address offline, before it is used
  trimmy_list_rules      every rule armed on the contract, read live
  trimmy_describe_rule   one rule in full
  trimmy_compose_rule    build the payment a human then signs themselves

This server cannot sign, cannot send, and holds no key. For a private rule it
refuses the threshold price outright, so the number never passes through the
agent: the person sends it to the enclave themselves.

Flare Coston2 testnet. Nothing here has run on Flare mainnet.
''';
