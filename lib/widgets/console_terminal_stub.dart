/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Stub for xterm on web platform.
 */

import 'package:flutter/material.dart';

/// Stub Terminal class for web platform
class Terminal {
  Terminal({int maxLines = 1000});

  void write(String data) {
    throw UnsupportedError('Terminal is not supported on web');
  }

  void Function(String)? onOutput;
}

/// Stub TerminalStyle class
class TerminalStyle {
  const TerminalStyle({double fontSize = 14});
}

/// Stub TerminalView widget for web platform
class TerminalView extends StatelessWidget {
  final Terminal terminal;
  final TerminalStyle textStyle;

  const TerminalView(
    this.terminal, {
    super.key,
    this.textStyle = const TerminalStyle(),
  });

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Terminal not supported on web',
        style: TextStyle(color: Colors.red),
      ),
    );
  }
}
