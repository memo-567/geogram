/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Console browser page - Direct terminal interface.
 */

import 'package:flutter/material.dart';
import 'console_terminal_page.dart';

/// Console browser page - directly shows the terminal
class ConsoleBrowserPage extends StatelessWidget {
  final String appPath;
  final String appTitle;

  const ConsoleBrowserPage({
    super.key,
    required this.appPath,
    required this.appTitle,
  });

  @override
  Widget build(BuildContext context) {
    // Directly show the terminal - no session management needed
    return const ConsoleTerminalPage();
  }
}
