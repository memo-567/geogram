/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Bluetooth Classic (SPP/RFCOMM) plugin for Linux
 * Uses BlueZ via DBus for Bluetooth Classic functionality
 *
 * This plugin provides RFCOMM client functionality for connecting
 * to Android devices running the Geogram SPP server.
 */

#include "bluetooth_classic_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>
#include <glib.h>

#include <cstring>
#include <errno.h>
#include <map>
#include <memory>
#include <string>
#include <unistd.h>
#include <vector>
#include <sys/socket.h>

// Bluetooth RFCOMM - check if system has the bluetooth library
#ifdef HAVE_BLUETOOTH
#include <bluetooth/bluetooth.h>
#include <bluetooth/rfcomm.h>
#define BLUETOOTH_AVAILABLE 1
#else
// Define minimal structures for compilation when headers not available
// RFCOMM socket calls will fail at runtime but won't crash
#ifndef AF_BLUETOOTH
#define AF_BLUETOOTH 31
#endif
#ifndef BTPROTO_RFCOMM
#define BTPROTO_RFCOMM 3
#endif
typedef struct { uint8_t b[6]; } bdaddr_t;
struct sockaddr_rc {
  sa_family_t rc_family;
  bdaddr_t rc_bdaddr;
  uint8_t rc_channel;
};
// Convert string "AA:BB:CC:DD:EE:FF" to bdaddr_t
// This function is used when libbluetooth-dev is installed
__attribute__((unused))
static inline void str2ba_compat(const char *str, bdaddr_t *ba) {
  int i;
  for (i = 5; i >= 0; i--, str += 3) {
    ba->b[i] = (uint8_t)strtol(str, nullptr, 16);
  }
}
#define str2ba str2ba_compat
#define BLUETOOTH_AVAILABLE 0
#endif

// BlueZ DBus constants
#define BLUEZ_SERVICE "org.bluez"
#define BLUEZ_ADAPTER_INTERFACE "org.bluez.Adapter1"
#define BLUEZ_DEVICE_INTERFACE "org.bluez.Device1"
#define DBUS_OBJECT_MANAGER_INTERFACE "org.freedesktop.DBus.ObjectManager"
#define DBUS_PROPERTIES_INTERFACE "org.freedesktop.DBus.Properties"

// SPP UUID for RFCOMM connections
#define SPP_UUID "00001101-0000-1000-8000-00805f9b34fb"

// Method channel name (must match Dart side)
#define CHANNEL_NAME "geogram/bluetooth_classic"

// Plugin data structure
typedef struct {
  FlPluginRegistrar* registrar;
  FlMethodChannel* channel;
  GDBusConnection* dbus_connection;
  gchar* adapter_path;
  std::map<std::string, int>* active_connections;
  GMutex connections_mutex;
} BluetoothClassicPluginData;

// Global plugin data
static BluetoothClassicPluginData* g_plugin_data = nullptr;

// Forward declarations
static void method_call_handler(FlMethodChannel* channel,
                                FlMethodCall* method_call,
                                gpointer user_data);
static FlMethodResponse* handle_is_available(BluetoothClassicPluginData* data);
static FlMethodResponse* handle_get_paired_devices(BluetoothClassicPluginData* data);
static FlMethodResponse* handle_connect(BluetoothClassicPluginData* data, FlValue* args);
static FlMethodResponse* handle_disconnect(BluetoothClassicPluginData* data, FlValue* args);
static FlMethodResponse* handle_send_data(BluetoothClassicPluginData* data, FlValue* args);
static FlMethodResponse* handle_is_connected(BluetoothClassicPluginData* data, FlValue* args);
static FlMethodResponse* handle_request_pairing(BluetoothClassicPluginData* data, FlValue* args);
static FlMethodResponse* handle_is_paired(BluetoothClassicPluginData* data, FlValue* args);
static FlMethodResponse* handle_get_local_mac_address(BluetoothClassicPluginData* data);
static gchar* find_default_adapter(BluetoothClassicPluginData* data);
static gchar* find_device_path(BluetoothClassicPluginData* data, const gchar* mac_address);
static int connect_rfcomm(const gchar* mac_address);

// Find the default Bluetooth adapter path
static gchar* find_default_adapter(BluetoothClassicPluginData* data) {
  if (data->dbus_connection == nullptr) {
    return nullptr;
  }

  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) result = g_dbus_connection_call_sync(
      data->dbus_connection,
      BLUEZ_SERVICE,
      "/",
      DBUS_OBJECT_MANAGER_INTERFACE,
      "GetManagedObjects",
      nullptr,
      G_VARIANT_TYPE("(a{oa{sa{sv}}})"),
      G_DBUS_CALL_FLAGS_NONE,
      -1,
      nullptr,
      &error);

  if (error != nullptr) {
    g_warning("BluetoothClassicPlugin: Failed to get managed objects: %s", error->message);
    return nullptr;
  }

  g_autoptr(GVariantIter) objects_iter = nullptr;
  g_variant_get(result, "(a{oa{sa{sv}}})", &objects_iter);

  const gchar* object_path;
  GVariantIter* interfaces_iter;

  while (g_variant_iter_next(objects_iter, "{&oa{sa{sv}}}", &object_path, &interfaces_iter)) {
    const gchar* interface_name;
    GVariantIter* properties_iter;

    while (g_variant_iter_next(interfaces_iter, "{&sa{sv}}", &interface_name, &properties_iter)) {
      if (strcmp(interface_name, BLUEZ_ADAPTER_INTERFACE) == 0) {
        g_variant_iter_free(properties_iter);
        g_variant_iter_free(interfaces_iter);
        return g_strdup(object_path);
      }
      g_variant_iter_free(properties_iter);
    }
    g_variant_iter_free(interfaces_iter);
  }

  return nullptr;
}

// Handle method calls from Dart
static void method_call_handler(FlMethodChannel* channel,
                                FlMethodCall* method_call,
                                gpointer user_data) {
  BluetoothClassicPluginData* data = static_cast<BluetoothClassicPluginData*>(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "isAvailable") == 0) {
    response = handle_is_available(data);
  } else if (strcmp(method, "canBeServer") == 0) {
    // Linux cannot be an SPP server (only client)
    g_autoptr(FlValue) result = fl_value_new_bool(FALSE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "canBeClient") == 0) {
    // Linux can be an RFCOMM client if adapter is available
    gboolean available = data->adapter_path != nullptr && BLUETOOTH_AVAILABLE;
    g_autoptr(FlValue) result = fl_value_new_bool(available);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "getPairedDevices") == 0) {
    response = handle_get_paired_devices(data);
  } else if (strcmp(method, "connect") == 0) {
    response = handle_connect(data, args);
  } else if (strcmp(method, "disconnect") == 0) {
    response = handle_disconnect(data, args);
  } else if (strcmp(method, "sendData") == 0) {
    response = handle_send_data(data, args);
  } else if (strcmp(method, "isConnected") == 0) {
    response = handle_is_connected(data, args);
  } else if (strcmp(method, "requestPairing") == 0) {
    response = handle_request_pairing(data, args);
  } else if (strcmp(method, "isPaired") == 0) {
    response = handle_is_paired(data, args);
  } else if (strcmp(method, "getLocalMacAddress") == 0) {
    response = handle_get_local_mac_address(data);
  } else if (strcmp(method, "startServer") == 0 ||
             strcmp(method, "stopServer") == 0) {
    // Server functionality not supported on Linux
    response = FL_METHOD_RESPONSE(fl_method_error_response_new(
        "UNSUPPORTED",
        "SPP server is not supported on Linux",
        nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("BluetoothClassicPlugin: Failed to send response: %s", error->message);
  }
}

// Check if Bluetooth is available
static FlMethodResponse* handle_is_available(BluetoothClassicPluginData* data) {
  gboolean available = data->dbus_connection != nullptr &&
                       data->adapter_path != nullptr &&
                       BLUETOOTH_AVAILABLE;
  g_autoptr(FlValue) result = fl_value_new_bool(available);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

// Get local Bluetooth MAC address
static FlMethodResponse* handle_get_local_mac_address(BluetoothClassicPluginData* data) {
  if (data->adapter_path == nullptr) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "NO_ADAPTER",
        "No Bluetooth adapter available",
        nullptr));
  }

  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) result = g_dbus_connection_call_sync(
      data->dbus_connection,
      BLUEZ_SERVICE,
      data->adapter_path,
      DBUS_PROPERTIES_INTERFACE,
      "Get",
      g_variant_new("(ss)", BLUEZ_ADAPTER_INTERFACE, "Address"),
      G_VARIANT_TYPE("(v)"),
      G_DBUS_CALL_FLAGS_NONE,
      -1,
      nullptr,
      &error);

  if (error != nullptr) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "DBUS_ERROR",
        error->message,
        nullptr));
  }

  g_autoptr(GVariant) address_variant = nullptr;
  g_variant_get(result, "(v)", &address_variant);
  const gchar* address = g_variant_get_string(address_variant, nullptr);

  g_autoptr(FlValue) fl_result = fl_value_new_string(address);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_result));
}

// Get list of paired devices
static FlMethodResponse* handle_get_paired_devices(BluetoothClassicPluginData* data) {
  if (data->dbus_connection == nullptr) {
    g_autoptr(FlValue) empty_list = fl_value_new_list();
    return FL_METHOD_RESPONSE(fl_method_success_response_new(empty_list));
  }

  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) result = g_dbus_connection_call_sync(
      data->dbus_connection,
      BLUEZ_SERVICE,
      "/",
      DBUS_OBJECT_MANAGER_INTERFACE,
      "GetManagedObjects",
      nullptr,
      G_VARIANT_TYPE("(a{oa{sa{sv}}})"),
      G_DBUS_CALL_FLAGS_NONE,
      -1,
      nullptr,
      &error);

  if (error != nullptr) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "DBUS_ERROR",
        error->message,
        nullptr));
  }

  g_autoptr(FlValue) devices_list = fl_value_new_list();

  g_autoptr(GVariantIter) objects_iter = nullptr;
  g_variant_get(result, "(a{oa{sa{sv}}})", &objects_iter);

  const gchar* object_path;
  GVariantIter* interfaces_iter;

  while (g_variant_iter_next(objects_iter, "{&oa{sa{sv}}}", &object_path, &interfaces_iter)) {
    const gchar* interface_name;
    GVariantIter* properties_iter;

    while (g_variant_iter_next(interfaces_iter, "{&sa{sv}}", &interface_name, &properties_iter)) {
      if (strcmp(interface_name, BLUEZ_DEVICE_INTERFACE) == 0) {
        gboolean paired = FALSE;
        const gchar* address = nullptr;
        const gchar* name = nullptr;

        const gchar* property_name;
        GVariant* property_value;

        while (g_variant_iter_next(properties_iter, "{&sv}", &property_name, &property_value)) {
          if (strcmp(property_name, "Paired") == 0) {
            paired = g_variant_get_boolean(property_value);
          } else if (strcmp(property_name, "Address") == 0) {
            address = g_variant_get_string(property_value, nullptr);
          } else if (strcmp(property_name, "Name") == 0) {
            name = g_variant_get_string(property_value, nullptr);
          }
          g_variant_unref(property_value);
        }

        if (paired && address != nullptr) {
          g_autoptr(FlValue) device_map = fl_value_new_map();
          fl_value_set_string_take(device_map, "address", fl_value_new_string(address));
          fl_value_set_string_take(device_map, "name",
              fl_value_new_string(name != nullptr ? name : "Unknown"));
          fl_value_append(devices_list, device_map);
        }
      }
      g_variant_iter_free(properties_iter);
    }
    g_variant_iter_free(interfaces_iter);
  }

  return FL_METHOD_RESPONSE(fl_method_success_response_new(devices_list));
}

// Find device object path by MAC address
static gchar* find_device_path(BluetoothClassicPluginData* data, const gchar* mac_address) {
  if (data->adapter_path == nullptr) {
    return nullptr;
  }

  // Convert MAC address format: AA:BB:CC:DD:EE:FF -> dev_AA_BB_CC_DD_EE_FF
  g_autofree gchar* mac_underscored = g_strdup(mac_address);
  for (gchar* p = mac_underscored; *p; p++) {
    if (*p == ':') *p = '_';
  }

  gchar* device_path = g_strdup_printf("%s/dev_%s", data->adapter_path, mac_underscored);

  // Verify device exists by trying to get its properties
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) result = g_dbus_connection_call_sync(
      data->dbus_connection,
      BLUEZ_SERVICE,
      device_path,
      DBUS_PROPERTIES_INTERFACE,
      "GetAll",
      g_variant_new("(s)", BLUEZ_DEVICE_INTERFACE),
      G_VARIANT_TYPE("(a{sv})"),
      G_DBUS_CALL_FLAGS_NONE,
      -1,
      nullptr,
      &error);

  if (error != nullptr) {
    g_free(device_path);
    return nullptr;
  }

  return device_path;
}

// Check if device is paired
static FlMethodResponse* handle_is_paired(BluetoothClassicPluginData* data, FlValue* args) {
  FlValue* mac_value = fl_value_lookup_string(args, "macAddress");
  if (mac_value == nullptr) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "INVALID_ARGUMENT",
        "macAddress is required",
        nullptr));
  }
  const gchar* mac_address = fl_value_get_string(mac_value);

  g_autofree gchar* device_path = find_device_path(data, mac_address);
  if (device_path == nullptr) {
    g_autoptr(FlValue) result = fl_value_new_bool(FALSE);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  }

  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) result = g_dbus_connection_call_sync(
      data->dbus_connection,
      BLUEZ_SERVICE,
      device_path,
      DBUS_PROPERTIES_INTERFACE,
      "Get",
      g_variant_new("(ss)", BLUEZ_DEVICE_INTERFACE, "Paired"),
      G_VARIANT_TYPE("(v)"),
      G_DBUS_CALL_FLAGS_NONE,
      -1,
      nullptr,
      &error);

  if (error != nullptr) {
    g_autoptr(FlValue) fl_result = fl_value_new_bool(FALSE);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_result));
  }

  g_autoptr(GVariant) paired_variant = nullptr;
  g_variant_get(result, "(v)", &paired_variant);
  gboolean paired = g_variant_get_boolean(paired_variant);

  g_autoptr(FlValue) fl_result = fl_value_new_bool(paired);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_result));
}

// Request pairing with device
static FlMethodResponse* handle_request_pairing(BluetoothClassicPluginData* data, FlValue* args) {
  FlValue* mac_value = fl_value_lookup_string(args, "macAddress");
  if (mac_value == nullptr) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "INVALID_ARGUMENT",
        "macAddress is required",
        nullptr));
  }
  const gchar* mac_address = fl_value_get_string(mac_value);

  g_autofree gchar* device_path = find_device_path(data, mac_address);
  if (device_path == nullptr) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "DEVICE_NOT_FOUND",
        "Device not found. Make sure it has been discovered via BLE first.",
        nullptr));
  }

  // Call Pair method on BlueZ device
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) result = g_dbus_connection_call_sync(
      data->dbus_connection,
      BLUEZ_SERVICE,
      device_path,
      BLUEZ_DEVICE_INTERFACE,
      "Pair",
      nullptr,
      nullptr,
      G_DBUS_CALL_FLAGS_NONE,
      60000,  // 60 second timeout for pairing
      nullptr,
      &error);

  if (error != nullptr) {
    // Check if already paired
    if (g_strrstr(error->message, "Already Paired") != nullptr ||
        g_strrstr(error->message, "AlreadyExists") != nullptr) {
      g_autoptr(FlValue) fl_result = fl_value_new_bool(TRUE);
      return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_result));
    }
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "PAIRING_FAILED",
        error->message,
        nullptr));
  }

  g_autoptr(FlValue) fl_result = fl_value_new_bool(TRUE);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_result));
}

// Create RFCOMM socket connection
// Note: This requires libbluetooth-dev to be installed
static int connect_rfcomm(const gchar* mac_address) {
#if BLUETOOTH_AVAILABLE
  struct sockaddr_rc addr = {0};
  int sock;

  // Create RFCOMM socket
  sock = socket(AF_BLUETOOTH, SOCK_STREAM, BTPROTO_RFCOMM);
  if (sock < 0) {
    g_warning("BluetoothClassicPlugin: Failed to create RFCOMM socket: %s", strerror(errno));
    return -1;
  }

  // Set up destination address
  addr.rc_family = AF_BLUETOOTH;
  addr.rc_channel = 1;  // SPP typically uses channel 1
  str2ba(mac_address, &addr.rc_bdaddr);

  // Connect to server
  if (connect(sock, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
    g_warning("BluetoothClassicPlugin: Failed to connect RFCOMM: %s", strerror(errno));
    close(sock);
    return -1;
  }

  g_message("BluetoothClassicPlugin: Connected to %s via RFCOMM", mac_address);
  return sock;
#else
  g_warning("BluetoothClassicPlugin: RFCOMM not available - libbluetooth-dev not installed");
  return -1;
#endif
}

// Connect to device via RFCOMM
static FlMethodResponse* handle_connect(BluetoothClassicPluginData* data, FlValue* args) {
  FlValue* mac_value = fl_value_lookup_string(args, "macAddress");
  if (mac_value == nullptr) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "INVALID_ARGUMENT",
        "macAddress is required",
        nullptr));
  }
  const gchar* mac_address = fl_value_get_string(mac_value);

  // Check if already connected
  g_mutex_lock(&data->connections_mutex);
  auto it = data->active_connections->find(mac_address);
  if (it != data->active_connections->end() && it->second >= 0) {
    g_mutex_unlock(&data->connections_mutex);
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  }
  g_mutex_unlock(&data->connections_mutex);

  // Verify device exists via DBus
  g_autofree gchar* device_path = find_device_path(data, mac_address);
  if (device_path == nullptr) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "DEVICE_NOT_FOUND",
        "Device not found",
        nullptr));
  }

  // Try to connect via BlueZ DBus first (for profile connection)
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) result = g_dbus_connection_call_sync(
      data->dbus_connection,
      BLUEZ_SERVICE,
      device_path,
      BLUEZ_DEVICE_INTERFACE,
      "ConnectProfile",
      g_variant_new("(s)", SPP_UUID),
      nullptr,
      G_DBUS_CALL_FLAGS_NONE,
      30000,  // 30 second timeout
      nullptr,
      &error);

  if (error != nullptr) {
    // If profile not available, try general Connect first
    if (g_strrstr(error->message, "DoesNotExist") != nullptr) {
      g_autoptr(GError) connect_error = nullptr;
      g_dbus_connection_call_sync(
          data->dbus_connection,
          BLUEZ_SERVICE,
          device_path,
          BLUEZ_DEVICE_INTERFACE,
          "Connect",
          nullptr,
          nullptr,
          G_DBUS_CALL_FLAGS_NONE,
          30000,
          nullptr,
          &connect_error);

      if (connect_error != nullptr) {
        g_warning("BluetoothClassicPlugin: DBus Connect failed: %s", connect_error->message);
        // Continue anyway - RFCOMM might still work
      }
    } else {
      g_warning("BluetoothClassicPlugin: ConnectProfile failed: %s", error->message);
    }
  }

  // Now establish RFCOMM socket connection
  int socket_fd = connect_rfcomm(mac_address);
  if (socket_fd < 0) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "RFCOMM_FAILED",
        "Failed to establish RFCOMM connection. Ensure libbluetooth-dev is installed.",
        nullptr));
  }

  g_mutex_lock(&data->connections_mutex);
  (*data->active_connections)[mac_address] = socket_fd;
  g_mutex_unlock(&data->connections_mutex);

  g_autoptr(FlValue) fl_result = fl_value_new_bool(TRUE);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_result));
}

// Disconnect from device
static FlMethodResponse* handle_disconnect(BluetoothClassicPluginData* data, FlValue* args) {
  FlValue* mac_value = fl_value_lookup_string(args, "macAddress");
  if (mac_value == nullptr) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "INVALID_ARGUMENT",
        "macAddress is required",
        nullptr));
  }
  const gchar* mac_address = fl_value_get_string(mac_value);

  g_mutex_lock(&data->connections_mutex);
  auto it = data->active_connections->find(mac_address);
  if (it != data->active_connections->end()) {
    if (it->second >= 0) {
      close(it->second);
    }
    data->active_connections->erase(it);
  }
  g_mutex_unlock(&data->connections_mutex);

  g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

// Check if connected
static FlMethodResponse* handle_is_connected(BluetoothClassicPluginData* data, FlValue* args) {
  FlValue* mac_value = fl_value_lookup_string(args, "macAddress");
  if (mac_value == nullptr) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "INVALID_ARGUMENT",
        "macAddress is required",
        nullptr));
  }
  const gchar* mac_address = fl_value_get_string(mac_value);

  g_mutex_lock(&data->connections_mutex);
  auto it = data->active_connections->find(mac_address);
  gboolean connected = (it != data->active_connections->end() && it->second >= 0);
  g_mutex_unlock(&data->connections_mutex);

  g_autoptr(FlValue) result = fl_value_new_bool(connected);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

// Send data to connected device
static FlMethodResponse* handle_send_data(BluetoothClassicPluginData* data, FlValue* args) {
  FlValue* mac_value = fl_value_lookup_string(args, "macAddress");
  FlValue* data_value = fl_value_lookup_string(args, "data");

  if (mac_value == nullptr || data_value == nullptr) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "INVALID_ARGUMENT",
        "macAddress and data are required",
        nullptr));
  }
  const gchar* mac_address = fl_value_get_string(mac_value);

  // Get the data bytes
  size_t data_length = fl_value_get_length(data_value);
  const uint8_t* bytes = fl_value_get_uint8_list(data_value);

  g_mutex_lock(&data->connections_mutex);
  auto it = data->active_connections->find(mac_address);
  if (it == data->active_connections->end() || it->second < 0) {
    g_mutex_unlock(&data->connections_mutex);
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "NOT_CONNECTED",
        "Not connected to device",
        nullptr));
  }

  int socket_fd = it->second;
  g_mutex_unlock(&data->connections_mutex);

  // Send data
  ssize_t bytes_written = write(socket_fd, bytes, data_length);
  if (bytes_written < 0) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "SEND_FAILED",
        strerror(errno),
        nullptr));
  }

  g_autoptr(FlValue) result = fl_value_new_int(bytes_written);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

// Cleanup function
static void cleanup_plugin_data(gpointer user_data) {
  BluetoothClassicPluginData* data = static_cast<BluetoothClassicPluginData*>(user_data);
  if (data == nullptr) return;

  // Close all active connections
  g_mutex_lock(&data->connections_mutex);
  if (data->active_connections) {
    for (auto& pair : *data->active_connections) {
      if (pair.second >= 0) {
        close(pair.second);
      }
    }
    delete data->active_connections;
    data->active_connections = nullptr;
  }
  g_mutex_unlock(&data->connections_mutex);

  g_mutex_clear(&data->connections_mutex);
  g_clear_pointer(&data->adapter_path, g_free);
  g_clear_object(&data->dbus_connection);
  g_free(data);

  if (g_plugin_data == data) {
    g_plugin_data = nullptr;
  }
}

// Plugin registration function
void bluetooth_classic_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  // Allocate plugin data
  BluetoothClassicPluginData* data = g_new0(BluetoothClassicPluginData, 1);
  data->registrar = FL_PLUGIN_REGISTRAR(g_object_ref(registrar));
  data->active_connections = new std::map<std::string, int>();
  g_mutex_init(&data->connections_mutex);

  // Connect to system DBus for BlueZ
  g_autoptr(GError) error = nullptr;
  data->dbus_connection = g_bus_get_sync(G_BUS_TYPE_SYSTEM, nullptr, &error);
  if (error != nullptr) {
    g_warning("BluetoothClassicPlugin: Failed to connect to system bus: %s", error->message);
  }

  // Find default Bluetooth adapter
  if (data->dbus_connection != nullptr) {
    data->adapter_path = find_default_adapter(data);
    if (data->adapter_path != nullptr) {
      g_message("BluetoothClassicPlugin: Found adapter at %s", data->adapter_path);
    } else {
      g_warning("BluetoothClassicPlugin: No Bluetooth adapter found");
    }
  }

  // Set up method channel
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  data->channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      CHANNEL_NAME,
      FL_METHOD_CODEC(codec));

  fl_method_channel_set_method_call_handler(
      data->channel,
      method_call_handler,
      data,
      cleanup_plugin_data);

  g_plugin_data = data;

  g_message("BluetoothClassicPlugin: Initialized (RFCOMM available: %s)",
            BLUETOOTH_AVAILABLE ? "yes" : "no");
}
