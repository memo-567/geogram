/// Command-line argument parser for geogram-cli
///
/// Supports the same switches as the desktop GUI for consistency.
/// See docs/command-line-switches.md for full documentation.

import 'dart:io';

/// Parsed command-line arguments for the CLI
class CliArgs {
  /// API server port (default: null, uses station settings)
  final int? port;

  /// Data directory path (default: platform-specific)
  final String? dataDir;

  /// Enable HTTP API on startup
  final bool httpApi;

  /// Enable Debug API on startup
  final bool debugApi;

  /// Create a new identity on startup
  final bool newIdentity;

  /// Identity type: 'client' or 'station'
  final String identityType;

  /// Nickname for the new identity
  final String? nickname;

  /// Skip intro/setup wizard
  final bool skipIntro;

  /// Localhost port range to scan (e.g., "5000-6000")
  final String? scanLocalhost;

  /// Internet-only mode (disable local network and BLE)
  final bool internetOnly;

  /// Disable automatic update checks
  final bool noUpdate;

  /// Enable verbose logging
  final bool verbose;

  /// Show help and exit
  final bool showHelp;

  /// Show version and exit
  final bool showVersion;

  /// Force setup wizard
  final bool forceSetup;

  /// Run in daemon mode (station command or --auto-station flag)
  final bool daemonMode;

  /// Auto-station mode (alias for daemon mode, for consistency with desktop app)
  final bool autoStation;

  /// Email DNS diagnostics - true if flag present, domain is optional
  final bool emailDnsCheck;

  /// Email DNS diagnostics domain (optional - auto-detects from config if not specified)
  final String? emailDnsDomain;

  /// Remaining positional arguments
  final List<String> positionalArgs;

  const CliArgs({
    this.port,
    this.dataDir,
    this.httpApi = false,
    this.debugApi = false,
    this.newIdentity = false,
    this.identityType = 'client',
    this.nickname,
    this.skipIntro = false,
    this.scanLocalhost,
    this.internetOnly = false,
    this.noUpdate = false,
    this.verbose = false,
    this.showHelp = false,
    this.showVersion = false,
    this.forceSetup = false,
    this.daemonMode = false,
    this.autoStation = false,
    this.emailDnsCheck = false,
    this.emailDnsDomain,
    this.positionalArgs = const [],
  });

  /// Parse command-line arguments
  static CliArgs parse(List<String> args) {
    int? port;
    String? dataDir;
    bool httpApi = false;
    bool debugApi = false;
    bool newIdentity = false;
    String identityType = 'client';
    String? nickname;
    bool skipIntro = false;
    String? scanLocalhost;
    bool internetOnly = false;
    bool noUpdate = false;
    bool verbose = false;
    bool showHelp = false;
    bool showVersion = false;
    bool forceSetup = false;
    bool daemonMode = false;
    bool autoStation = false;
    bool emailDnsCheck = false;
    String? emailDnsDomain;
    final positionalArgs = <String>[];

    for (int i = 0; i < args.length; i++) {
      final arg = args[i];

      // --port=PORT or -p PORT
      if (arg.startsWith('--port=')) {
        port = int.tryParse(arg.substring('--port='.length));
      } else if (arg == '--port' && i + 1 < args.length) {
        port = int.tryParse(args[++i]);
      } else if (arg == '-p' && i + 1 < args.length) {
        port = int.tryParse(args[++i]);
      }
      // --data-dir=PATH or -d PATH
      else if (arg.startsWith('--data-dir=')) {
        dataDir = arg.substring('--data-dir='.length);
      } else if (arg == '--data-dir' && i + 1 < args.length) {
        dataDir = args[++i];
      } else if (arg == '-d' && i + 1 < args.length) {
        dataDir = args[++i];
      }
      // --http-api
      else if (arg == '--http-api') {
        httpApi = true;
      }
      // --debug-api
      else if (arg == '--debug-api') {
        debugApi = true;
      }
      // --new-identity
      else if (arg == '--new-identity') {
        newIdentity = true;
      }
      // --identity-type=TYPE
      else if (arg.startsWith('--identity-type=')) {
        identityType = arg.substring('--identity-type='.length);
      } else if (arg == '--identity-type' && i + 1 < args.length) {
        identityType = args[++i];
      }
      // --nickname=NAME
      else if (arg.startsWith('--nickname=')) {
        nickname = arg.substring('--nickname='.length);
      } else if (arg == '--nickname' && i + 1 < args.length) {
        nickname = args[++i];
      }
      // --skip-intro
      else if (arg == '--skip-intro') {
        skipIntro = true;
      }
      // --scan-localhost=RANGE
      else if (arg.startsWith('--scan-localhost=')) {
        scanLocalhost = arg.substring('--scan-localhost='.length);
      } else if (arg == '--scan-localhost' && i + 1 < args.length) {
        scanLocalhost = args[++i];
      }
      // --internet-only
      else if (arg == '--internet-only') {
        internetOnly = true;
      }
      // --no-update
      else if (arg == '--no-update') {
        noUpdate = true;
      }
      // --verbose
      else if (arg == '--verbose') {
        verbose = true;
      }
      // --help or -h
      else if (arg == '--help' || arg == '-h') {
        showHelp = true;
      }
      // --version or -v
      else if (arg == '--version' || arg == '-v') {
        showVersion = true;
      }
      // --setup or -s
      else if (arg == '--setup' || arg == '-s') {
        forceSetup = true;
      }
      // --auto-station (alias for daemon mode, for consistency with desktop app)
      else if (arg == '--auto-station') {
        autoStation = true;
        daemonMode = true;
      }
      // --email-dns or --email-dns=DOMAIN
      else if (arg == '--email-dns') {
        emailDnsCheck = true;
        // Check if next arg is a domain (not another flag)
        if (i + 1 < args.length && !args[i + 1].startsWith('-')) {
          emailDnsDomain = args[++i];
        }
      } else if (arg.startsWith('--email-dns=')) {
        emailDnsCheck = true;
        emailDnsDomain = arg.substring('--email-dns='.length);
      }
      // Positional arguments (first one might be 'station' for daemon mode)
      else if (!arg.startsWith('-')) {
        if (positionalArgs.isEmpty && arg == 'station') {
          daemonMode = true;
        }
        positionalArgs.add(arg);
      }
    }

    return CliArgs(
      port: port,
      dataDir: dataDir,
      httpApi: httpApi,
      debugApi: debugApi,
      newIdentity: newIdentity,
      identityType: identityType,
      nickname: nickname,
      skipIntro: skipIntro,
      scanLocalhost: scanLocalhost,
      internetOnly: internetOnly,
      noUpdate: noUpdate,
      verbose: verbose,
      showHelp: showHelp,
      showVersion: showVersion,
      forceSetup: forceSetup,
      daemonMode: daemonMode,
      autoStation: autoStation,
      emailDnsCheck: emailDnsCheck,
      emailDnsDomain: emailDnsDomain,
      positionalArgs: positionalArgs,
    );
  }

  /// Print help message
  static void printHelp() {
    stdout.writeln('''
Geogram CLI - Command-line interface for Geogram

Usage: geogram-cli [options] [command]

Options:
  --port=PORT, -p PORT       Station server port (default: 3456)
  --data-dir=PATH, -d PATH   Data directory path
  --http-api                 Enable HTTP API on startup
  --debug-api                Enable Debug API on startup
  --new-identity             Create a new identity on startup
  --identity-type=TYPE       Identity type: 'client' or 'station' (default: client)
  --nickname=NAME            Nickname for the new identity
  --skip-intro               Skip intro/setup wizard
  --scan-localhost=RANGE     Scan localhost ports (e.g., 5000-6000)
  --internet-only            Disable local network discovery
  --no-update                Disable automatic update checks
  --verbose                  Enable verbose logging
  --setup, -s                Force setup wizard
  --auto-station             Auto-start station server (daemon mode)
  --email-dns[=DOMAIN]       Run email DNS diagnostics and exit (auto-detects domain)
  --help, -h                 Show this help message
  --version, -v              Show version information

Commands:
  station                    Run in daemon mode (same as --auto-station)

Examples:
  # Start CLI with default settings
  geogram-cli

  # Create a new station identity and start the server
  geogram-cli --new-identity --identity-type=station --nickname="MyStation" --port=8080

  # Run station in daemon mode (two equivalent ways)
  geogram-cli station --port=80 --data-dir=/var/geogram
  geogram-cli --auto-station --port=80 --data-dir=/var/geogram

  # Start with fresh identity for testing
  geogram-cli --new-identity --skip-intro --data-dir=/tmp/test

  # Check email DNS configuration (auto-detects domain from config)
  geogram-cli --email-dns

  # Check email DNS for a specific domain
  geogram-cli --email-dns=example.com

For more information, see docs/command-line-switches.md
''');
  }

  /// Print version information
  static void printVersion() {
    stdout.writeln('Geogram CLI version 1.6.34');
  }

  /// Whether the identity type is station
  bool get isStation => identityType.toLowerCase() == 'station';

  /// Whether the identity type is client
  bool get isClient => identityType.toLowerCase() == 'client';

  @override
  String toString() {
    return 'CliArgs(port: $port, dataDir: $dataDir, httpApi: $httpApi, '
        'debugApi: $debugApi, newIdentity: $newIdentity, identityType: $identityType, '
        'nickname: $nickname, skipIntro: $skipIntro, scanLocalhost: $scanLocalhost, '
        'internetOnly: $internetOnly, noUpdate: $noUpdate, verbose: $verbose, '
        'daemonMode: $daemonMode, emailDnsCheck: $emailDnsCheck, emailDnsDomain: $emailDnsDomain)';
  }
}
