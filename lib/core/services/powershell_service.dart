import 'dart:convert';
import 'dart:io';

/// Thrown when PowerShell fails or returns something we cannot parse.
class PowerShellException implements Exception {
  PowerShellException(this.message);
  final String message;

  @override
  String toString() => 'PowerShellException: $message';
}

/// Runs PowerShell scripts and decodes their JSON output.
///
/// Scripts are passed with `-EncodedCommand` (base64 UTF-16LE) so that quotes
/// and newlines in the script never need escaping on the command line.
class PowerShellService {
  const PowerShellService();

  static const _preamble =
      r"$ProgressPreference='SilentlyContinue';$ErrorActionPreference='Stop';"
      r'[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;';

  /// Runs [script] and returns the decoded JSON written to stdout
  /// (the script should end with `ConvertTo-Json -Compress`).
  Future<Object?> runJson(
    String script, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (!Platform.isWindows) {
      throw PowerShellException('PowerShell diagnostics require Windows.');
    }

    final result = await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-ExecutionPolicy',
        'Bypass',
        '-EncodedCommand',
        _encode('$_preamble$script'),
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    ).timeout(timeout, onTimeout: () {
      throw PowerShellException('PowerShell timed out after ${timeout.inSeconds}s.');
    });

    if (result.exitCode != 0) {
      final err = '${result.stderr}'.trim();
      throw PowerShellException(err.isEmpty ? 'Exit code ${result.exitCode}' : err);
    }

    final out = '${result.stdout}'.trim();
    if (out.isEmpty) return null;
    try {
      return jsonDecode(out);
    } on FormatException catch (e) {
      throw PowerShellException('Invalid JSON from PowerShell: ${e.message}');
    }
  }

  static String _encode(String script) {
    final bytes = <int>[];
    for (final unit in script.codeUnits) {
      bytes
        ..add(unit & 0xFF)
        ..add(unit >> 8);
    }
    return base64.encode(bytes);
  }
}
