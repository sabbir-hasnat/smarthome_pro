import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
// <-- এই লাইনটি যোগ করুন
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartHomeProApp());
}

// ==========================================
// 1. CONSTANTS & UUIDs (MATCHING ESP32)
// ==========================================
const String kServiceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
const String kCharCmdUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
const String kCharStateUuid = "d4e5f6a7-47f2-5799-c8a6-fb18472c37b9";
const String kMqttBroker = "broker.hivemq.com";
const int kMqttPort = 1883;

// ==========================================
// 2. DATA MODELS
// ==========================================
class SavedDevice {
  String deviceId; // e.g., SHN-A1B2C3D4
  String name;     // e.g., Master Bedroom
  String pin;      // e.g., 123456

  SavedDevice({required this.deviceId, required this.name, required this.pin});

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'name': name,
        'pin': pin,
      };

  factory SavedDevice.fromJson(Map<String, dynamic> json) => SavedDevice(
        deviceId: json['deviceId'],
        name: json['name'],
        pin: json['pin'],
      );
}

// ==========================================
// 3. ROOT APP WIDGET
// ==========================================
class SmartHomeProApp extends StatelessWidget {
  const SmartHomeProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartHome Pro BD',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        primaryColor: const Color(0xFF38BDF8),
        cardColor: const Color(0xFF1E293B),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF38BDF8),
          secondary: Color(0xFF818CF8),
          surface: Color(0xFF1E293B),
        ),
      ),
      home: const MultiDeviceListScreen(),
    );
  }
}

// ==========================================
// 4. MULTI-DEVICE LOGIN & MANAGER SCREEN
// ==========================================
class MultiDeviceListScreen extends StatefulWidget {
  const MultiDeviceListScreen({super.key});

  @override
  State<MultiDeviceListScreen> createState() => _MultiDeviceListScreenState();
}

class _MultiDeviceListScreenState extends State<MultiDeviceListScreen> {
  List<SavedDevice> _devices = [];

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _loadSavedDevices();
  }

  Future<void> _requestPermissions() async {
    if (kIsWeb) return;
    try {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
    } catch (e) {
      debugPrint("Permission skipped: $e");
    }
  }

  Future<void> _loadSavedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final String? rawList = prefs.getString('saved_devices');
    if (rawList != null) {
      final List decoded = jsonDecode(rawList);
      setState(() {
        _devices = decoded.map((e) => SavedDevice.fromJson(e)).toList();
      });
    }
  }

  Future<void> _saveDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_devices.map((e) => e.toJson()).toList());
    await prefs.setString('saved_devices', encoded);
  }

  void _addOrUpdateDevice(SavedDevice newDev) {
    setState(() {
      final idx = _devices.indexWhere((d) => d.deviceId == newDev.deviceId);
      if (idx >= 0) {
        _devices[idx] = newDev;
      } else {
        _devices.add(newDev);
      }
    });
    _saveDevices();
  }

  void _deleteDevice(String id) {
    setState(() {
      _devices.removeWhere((d) => d.deviceId == id);
    });
    _saveDevices();
  }

  void _showAddDeviceModal({String? prefilledId}) {
    final idCtrl = TextEditingController(text: prefilledId ?? "SHN-");
    final nameCtrl = TextEditingController(text: "Living Room");
    final pinCtrl = TextEditingController(text: "123456");

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Login / Add ESP32 Device",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: "Room / Device Name",
                prefixIcon: Icon(Icons.meeting_room_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: idCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: "Unique Device ID (e.g. SHN-A1B2C3D4)",
                prefixIcon: Icon(Icons.qr_code),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pinCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Device Login PIN (Default: 123456)",
                prefixIcon: Icon(Icons.lock_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.login),
                label: const Text("Save & Login to Device"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF38BDF8),
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  final id = idCtrl.text.trim().toUpperCase();
                  final name = nameCtrl.text.trim();
                  final pin = pinCtrl.text.trim();
                  if (id.isEmpty || pin.isEmpty) return;

                  final dev = SavedDevice(deviceId: id, name: name, pin: pin);
                  _addOrUpdateDevice(dev);
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DeviceDashboardScreen(device: dev),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBleScannerModal() {
    if (!kIsWeb) {
      try {
        FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));
      } catch (e) {
        debugPrint("BLE Scan Error: $e");
      }
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Nearby ESP32 Devices (BLE)",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    if (!kIsWeb) {
                      FlutterBluePlus.startScan(
                          timeout: const Duration(seconds: 5));
                    }
                  },
                ),
              ],
            ),
            const Divider(),
            SizedBox(
              height: 260,
              child: kIsWeb
                  ? const Center(
                      child: Text("BLE Scan shudhu Android/iOS-e kaj korbe."))
                  : StreamBuilder<List<ScanResult>>(
                      stream: FlutterBluePlus.scanResults,
                      builder: (context, snapshot) {
                        final results = (snapshot.data ?? []).where((r) {
                          final name = r.device.platformName;
                          return name.startsWith("SHN-") || name.isNotEmpty;
                        }).toList();

                        if (results.isEmpty) {
                          return const Center(
                            child: Text("Scanning for SHN-XXXXXXXX devices..."),
                          );
                        }

                        return ListView.builder(
                          itemCount: results.length,
                          itemBuilder: (c, i) {
                            final r = results[i];
                            final name = r.device.platformName;
                            return ListTile(
                              leading: const Icon(Icons.bluetooth,
                                  color: Color(0xFF38BDF8)),
                              title: Text(name),
                              subtitle: Text("RSSI: ${r.rssi} dBm"),
                              trailing: ElevatedButton(
                                child: const Text("Select"),
                                onPressed: () {
                                  FlutterBluePlus.stopScan();
                                  Navigator.pop(ctx);
                                  _showAddDeviceModal(prefilledId: name);
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("SmartHome Pro Devices"),
        backgroundColor: const Color(0xFF1E293B),
        actions: [
          IconButton(
            tooltip: "Scan BLE Devices",
            icon: const Icon(Icons.bluetooth_searching),
            onPressed: _showBleScannerModal,
          ),
        ],
      ),
      body: _devices.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.developer_board,
                        size: 72, color: Colors.white38),
                    const SizedBox(height: 16),
                    const Text(
                      "Kono ESP32 Device Add Kora Hoyni",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Nicher '+' button-e click kore Device ID o PIN diye unlimited ESP32 add korun othoba BLE Scan korun.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.bluetooth_searching),
                      label: const Text("Scan Nearby BLE Devices"),
                      onPressed: _showBleScannerModal,
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _devices.length,
              itemBuilder: (ctx, i) {
                final dev = _devices[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    leading: CircleAvatar(
                      backgroundColor:
                          const Color(0xFF38BDF8).withValues(alpha: 0.15),
                      child: const Icon(Icons.memory, color: Color(0xFF38BDF8)),
                    ),
                    title: Text(
                      dev.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 17),
                    ),
                    subtitle: Text("ID: ${dev.deviceId}  •  BLE + MQTT"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.redAccent),
                          onPressed: () => _deleteDevice(dev.deviceId),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DeviceDashboardScreen(device: dev),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF38BDF8),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text("Add Device"),
        onPressed: () => _showAddDeviceModal(),
      ),
    );
  }
}

// ==========================================
// 5. DEVICE DASHBOARD (BLE + MQTT AUTO-SWITCH)
// ==========================================
class DeviceDashboardScreen extends StatefulWidget {
  final SavedDevice device;
  const DeviceDashboardScreen({super.key, required this.device});

  @override
  State<DeviceDashboardScreen> createState() => _DeviceDashboardScreenState();
}

class _DeviceDashboardScreenState extends State<DeviceDashboardScreen> {
  // Transport Connection States
  bool _bleConnected = false;
  bool _mqttConnected = false;
  bool _deviceOnlineMqtt = false;
  String _preferredMode = "AUTO"; // AUTO, BLE, MQTT

  // BLE Objects
  BluetoothDevice? _bleDevice;
  BluetoothCharacteristic? _bleCmdChar;
  StreamSubscription? _bleNotifySub;
  StreamSubscription? _bleConnSub;
  StreamSubscription? _bleScanSub;

  // MQTT Objects
  MqttServerClient? _mqttClient;

  // Device Relay & Telemetry States
  bool _lightState = false;
  bool _fanState = false;
  String _lastSyncSource = "Connecting...";
  String _authStatus = "Verifying PIN...";

  Map<String, dynamic> _deviceInfo = {};
  Map<String, dynamic> _telemetry = {};

  @override
  void initState() {
    super.initState();
    _initHybridConnection();
  }

  @override
  void dispose() {
    _bleScanSub?.cancel();
    _bleNotifySub?.cancel();
    _bleConnSub?.cancel();
    _bleDevice?.disconnect();
    _mqttClient?.disconnect();
    super.dispose();
  }

  void _initHybridConnection() {
    _connectBle();
    _connectMqtt();
  }

  // ------------------------------------------
  // A. BLE CONNECTION & AUTO-DISCOVERY
  // ------------------------------------------
  Future<void> _connectBle() async {
    if (kIsWeb) return;
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
      _bleScanSub = FlutterBluePlus.scanResults.listen((results) async {
        for (ScanResult r in results) {
          if (r.device.platformName == widget.device.deviceId) {
            await FlutterBluePlus.stopScan();
            _bleDevice = r.device;

            _bleConnSub = _bleDevice!.connectionState.listen((state) {
              if (mounted) {
                setState(() {
                  _bleConnected =
                      (state == BluetoothConnectionState.connected);
                });
              }
            });

await _bleDevice!.connect(
              license: License.free,
              mtu: 512,
              autoConnect: false,
            );

            List<BluetoothService> services =
                await _bleDevice!.discoverServices();

            for (var s in services) {
              if (s.uuid.toString().toLowerCase() == kServiceUuid) {
                for (var c in s.characteristics) {
                  final uuid = c.uuid.toString().toLowerCase();
                  if (uuid == kCharCmdUuid) {
                    _bleCmdChar = c;
                  } else if (uuid == kCharStateUuid) {
                    await c.setNotifyValue(true);
                    _bleNotifySub = c.onValueReceived.listen((val) {
                      _parseIncomingJson(utf8.decode(val), "BLE");
                    });
                  }
                }
              }
            }

            // Perform Login handshake over BLE
            _sendCommand({"cmd": "login"});
            break;
          }
        }
      });
    } catch (e) {
      debugPrint("BLE Error (Ignored on Emulator): $e");
    }
  }

  // ------------------------------------------
  // B. MQTT CLOUD CONNECTION
  // ------------------------------------------
  Future<void> _connectMqtt() async {
    final clientId =
        "FlutterApp-${widget.device.deviceId}-${Random().nextInt(9999)}";
    _mqttClient = MqttServerClient(kMqttBroker, clientId);
    _mqttClient!.port = kMqttPort;
    _mqttClient!.keepAlivePeriod = 30;
    _mqttClient!.autoReconnect = true;

    _mqttClient!.onConnected = () {
      if (!mounted) return;
      setState(() => _mqttConnected = true);

      final stateTopic = "iot/smarthome/${widget.device.deviceId}/state";
      final availTopic =
          "iot/smarthome/${widget.device.deviceId}/availability";

      _mqttClient!.subscribe(stateTopic, MqttQos.atLeastOnce);
      _mqttClient!.subscribe(availTopic, MqttQos.atLeastOnce);

      _mqttClient!.updates!
          .listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
        final recMess = c![0].payload as MqttPublishMessage;
        final topic = c[0].topic;
        final payload =
            MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

        if (topic.endsWith("/availability")) {
          if (mounted) {
            setState(() => _deviceOnlineMqtt = (payload == "ONLINE"));
          }
        } else {
          _parseIncomingJson(payload, "MQTT");
        }
      });

      // Request initial login status via MQTT
      _sendCommand({"cmd": "login"});
    };

    _mqttClient!.onDisconnected = () {
      if (mounted) setState(() => _mqttConnected = false);
    };

    try {
      await _mqttClient!.connect();
    } catch (e) {
      debugPrint("MQTT Error: $e");
      _mqttClient?.disconnect();
    }
  }

  // ------------------------------------------
  // C. HYBRID AUTO-SWITCHING COMMAND SENDER
  // ------------------------------------------
  Future<void> _sendCommand(Map<String, dynamic> payload) async {
    payload["pin"] = widget.device.pin;
    final String jsonStr = jsonEncode(payload);

    bool useBle = false;
    if (_preferredMode == "BLE") {
      useBle = true;
    } else if (_preferredMode == "MQTT") {
      useBle = false;
    } else {
      useBle = _bleConnected && _bleCmdChar != null;
    }

    if (useBle && _bleConnected && _bleCmdChar != null) {
      try {
        await _bleCmdChar!.write(utf8.encode(jsonStr), withoutResponse: false);
        return;
      } catch (e) {
        debugPrint("BLE Write failed, falling back to MQTT: $e");
      }
    }

    if (_mqttConnected && _mqttClient != null) {
      final cmdTopic = "iot/smarthome/${widget.device.deviceId}/cmd";
      final builder = MqttClientPayloadBuilder();
      builder.addString(jsonStr);
      _mqttClient!.publishMessage(
          cmdTopic, MqttQos.atLeastOnce, builder.payload!);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("UI Preview Mode: BLE/MQTT waiting for ESP32...")),
        );
      }
    }
  }

  // ------------------------------------------
  // D. INCOMING JSON STATE PARSER
  // ------------------------------------------
  void _parseIncomingJson(String rawJson, String transport) {
    try {
      final Map<String, dynamic> data = jsonDecode(rawJson);

      if (data['status'] == 'UNAUTHORIZED') {
        if (mounted) {
          setState(() => _authStatus = "WRONG PIN! Access Denied");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text(data['message'] ?? "Invalid Device PIN!"),
            ),
          );
        }
        return;
      }

      if (data.containsKey('message')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("${data['status']}: ${data['message']}")),
          );
        }
      }

      if (data.containsKey('state')) {
        if (mounted) {
          setState(() {
            _authStatus = "Authenticated";
            _lightState = data['state']['light'] ?? false;
            _fanState = data['state']['fan'] ?? false;
            _lastSyncSource = "$transport (${data['source'] ?? 'SYNC'})";
            _deviceOnlineMqtt = data['online'] ?? true;
            if (data.containsKey('info')) _deviceInfo = data['info'];
            if (data.containsKey('telemetry')) _telemetry = data['telemetry'];
          });
        }
      }
    } catch (e) {
      debugPrint("JSON Parse Error: $e");
    }
  }

  // ------------------------------------------
  // E. SETTINGS & WIFI PROVISIONING MODAL
  // ------------------------------------------
  void _showSettingsModal() {
    final ssidCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final newPinCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "ESP32 Provisioning & Security",
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text("1. Update ESP32 WiFi Credentials (via BLE/MQTT)"),
              const SizedBox(height: 8),
              TextField(
                controller: ssidCtrl,
                decoration: const InputDecoration(
                  labelText: "New WiFi SSID",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "New WiFi Password",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.wifi),
                label: const Text("Send WiFi Config to ESP32"),
                onPressed: () {
                  _sendCommand({
                    "cmd": "set_wifi",
                    "ssid": ssidCtrl.text.trim(),
                    "pass": passCtrl.text.trim(),
                  });
                  Navigator.pop(ctx);
                },
              ),
              const Divider(height: 32),
              const Text("2. Change Device Security PIN"),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: newPinCtrl,
                      decoration: const InputDecoration(
                        labelText: "New PIN (4+ chars)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    child: const Text("Update PIN"),
                    onPressed: () {
                      final np = newPinCtrl.text.trim();
                      if (np.length >= 4) {
                        _sendCommand({"cmd": "set_pin", "new_pin": np});
                        widget.device.pin = np;
                        Navigator.pop(ctx);
                      }
                    },
                  ),
                ],
              ),
              const Divider(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.restart_alt, color: Colors.amber),
                    label: const Text("Reboot ESP32"),
                    onPressed: () {
                      _sendCommand({"cmd": "reboot"});
                      Navigator.pop(ctx);
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.delete_forever,
                        color: Colors.redAccent),
                    label: const Text("Factory Reset"),
                    onPressed: () {
                      _sendCommand({"cmd": "factory_reset"});
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------
  // F. DASHBOARD UI BUILDER
  // ------------------------------------------
  @override
  Widget build(BuildContext context) {
    final String activeRoute = (_preferredMode == "BLE" ||
            (_preferredMode == "AUTO" && _bleConnected))
        ? "BLE Direct (Local)"
        : (_mqttConnected ? "MQTT Cloud (Internet)" : "Disconnected");

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.device.name, style: const TextStyle(fontSize: 18)),
            Text(
              widget.device.deviceId,
              style: const TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        actions: [
          IconButton(
            tooltip: "Refresh Status",
            icon: const Icon(Icons.sync),
            onPressed: () => _sendCommand({"cmd": "get_status"}),
          ),
          IconButton(
            tooltip: "Device Provisioning & Settings",
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsModal,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. CONNECTION STATUS BANNER
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildStatusBadge(
                        icon: Icons.bluetooth,
                        label: _bleConnected ? "BLE Ready" : "BLE Away",
                        active: _bleConnected,
                      ),
                      _buildStatusBadge(
                        icon: Icons.cloud_done,
                        label: (_mqttConnected && _deviceOnlineMqtt)
                            ? "Cloud Online"
                            : "Cloud Offline",
                        active: _mqttConnected && _deviceOnlineMqtt,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _authStatus == "Authenticated"
                              ? Colors.green.withValues(alpha: 0.2)
                              : Colors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _authStatus,
                          style: TextStyle(
                            fontSize: 12,
                            color: _authStatus == "Authenticated"
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Active Route: $activeRoute",
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF38BDF8)),
                      ),
                      DropdownButton<String>(
                        value: _preferredMode,
                        underline: const SizedBox(),
                        isDense: true,
                        items: const [
                          DropdownMenuItem(
                              value: "AUTO", child: Text("Auto Switch")),
                          DropdownMenuItem(
                              value: "BLE", child: Text("BLE Only")),
                          DropdownMenuItem(
                              value: "MQTT", child: Text("Cloud Only")),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _preferredMode = v);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 2. RELAY CONTROL CARDS (LIGHT & FAN)
            Row(
              children: [
                Expanded(
                  child: _buildApplianceCard(
                    title: "Room Light",
                    subtitle: "Relay IN1 (D26)",
                    icon: Icons.lightbulb,
                    isOn: _lightState,
                    activeColor: Colors.amber,
                    onToggle: (val) {
                      setState(() => _lightState = val);
                      _sendCommand({"cmd": "control", "light": val});
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildApplianceCard(
                    title: "Ceiling Fan",
                    subtitle: "Relay IN2 (D27)",
                    icon: Icons.wind_power,
                    isOn: _fanState,
                    activeColor: const Color(0xFF38BDF8),
                    onToggle: (val) {
                      setState(() => _fanState = val);
                      _sendCommand({"cmd": "control", "fan": val});
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 3. LIVE TELEMETRY DIAGNOSTICS
            const Text(
              "Live Hardware Telemetry",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _buildInfoRow("Last Sync Trigger", _lastSyncSource),
                  _buildInfoRow("WiFi Signal (RSSI)",
                      "${_telemetry['wifi_rssi'] ?? '--'} dBm"),
                  _buildInfoRow(
                      "Local IP Address", "${_telemetry['ip'] ?? '0.0.0.0'}"),
                  _buildInfoRow(
                      "System Uptime", "${_telemetry['uptime_sec'] ?? 0} sec"),
                  _buildInfoRow("Free Heap RAM",
                      "${_telemetry['free_heap'] ?? '--'} bytes"),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 4. INDUSTRIAL FIRMWARE & MANUFACTURING METADATA
            const Text(
              "Industrial Device Specification",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _buildInfoRow("Unique Device ID", widget.device.deviceId),
                  _buildInfoRow("Manufacturer",
                      "${_deviceInfo['manufacturer'] ?? 'SmartHome Tech BD'}"),
                  _buildInfoRow("Device Model",
                      "${_deviceInfo['model'] ?? 'SHN-2CH-PRO'}"),
                  _buildInfoRow("Firmware Version",
                      "${_deviceInfo['fw_version'] ?? 'FW-v2.4.0-PROD'}"),
                  _buildInfoRow("Hardware Revision",
                      "${_deviceInfo['hw_version'] ?? 'HW-v1.2.0'}"),
                  _buildInfoRow("Manufacture Date",
                      "${_deviceInfo['mfg_date'] ?? '2026-10-15'}"),
                  _buildInfoRow("Release Date",
                      "${_deviceInfo['release_date'] ?? '2026-10-17'}"),
                  _buildInfoRow(
                      "Build Timestamp", "${_deviceInfo['build_time'] ?? '--'}"),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge({
    required IconData icon,
    required String label,
    required bool active,
  }) {
    return Row(
      children: [
        Icon(icon,
            size: 18, color: active ? const Color(0xFF38BDF8) : Colors.white38),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : Colors.white38,
          ),
        ),
      ],
    );
  }

  Widget _buildApplianceCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isOn,
    required Color activeColor,
    required ValueChanged<bool> onToggle,
  }) {
    return GestureDetector(
      onTap: () => onToggle(!isOn),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isOn
              ? activeColor.withValues(alpha: 0.18)
              : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isOn ? activeColor : Colors.white10,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon,
                    size: 36, color: isOn ? activeColor : Colors.white54),
                Switch(
                  value: isOn,
                  activeThumbColor: activeColor,
                  onChanged: onToggle,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              isOn ? "$subtitle • ON" : "$subtitle • OFF",
              style: TextStyle(
                fontSize: 12,
                color: isOn ? activeColor : Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60)),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}