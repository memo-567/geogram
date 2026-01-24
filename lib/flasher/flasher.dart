/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Flasher module for flashing ESP32 and other USB devices
///
/// Usage:
/// ```dart
/// import 'package:geogram/flasher/flasher.dart';
///
/// final service = FlasherService.withPath('flasher');
/// final devices = await service.storage.loadAllDevices();
/// ```

// Models
export 'models/device_definition.dart';
export 'models/flash_progress.dart';

// Protocols
export 'protocols/flash_protocol.dart';
export 'protocols/esptool_protocol.dart';
export 'protocols/protocol_registry.dart';

// Serial
export 'serial/serial_port.dart';
export 'serial/serial_port_desktop.dart';
export 'serial/serial_port_android.dart';

// Services
export 'services/flasher_service.dart';
export 'services/flasher_storage_service.dart';

// Pages
export 'pages/flasher_page.dart';

// Widgets
export 'widgets/device_card.dart';
export 'widgets/flash_progress_widget.dart';
