/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Bluetooth Classic (SPP/RFCOMM) plugin for Linux
 * Uses BlueZ via DBus for Bluetooth Classic functionality
 */

#ifndef BLUETOOTH_CLASSIC_PLUGIN_H_
#define BLUETOOTH_CLASSIC_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

/**
 * Initialize the Bluetooth Classic plugin
 *
 * @param registrar The plugin registrar
 */
void bluetooth_classic_plugin_register_with_registrar(FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // BLUETOOTH_CLASSIC_PLUGIN_H_
