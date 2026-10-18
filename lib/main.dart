import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app_settings_controller.dart';
import 'src/device_message_parser.dart';

const String kServiceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
const String kCharCmdUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';
const String kCharStateUuid = 'd4e5f6a7-47f2-5799-c8a6-fb18472c37b9';

const String kMqttBroker = 'broker.hivemq.com';
const int kMqttPort = 1883;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('en');
  await initializeDateFormatting('bn');

  final settings = AppSettingsController();
  await settings.load();

  runApp(SmartHomeProApp(settings: settings));
}

class SavedDevice {
  SavedDevice({
    required this.deviceId,
    required this.name,
    required this.pin,
  });

  final String deviceId;
  final String name;
  String pin;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'name': name,
        'pin': pin,
      };

  factory SavedDevice.fromJson(Map<String, dynamic> json) {
    return SavedDevice(
      deviceId: (json['deviceId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      pin: (json['pin'] ?? '').toString(),
    );
  }
}

class SmartHomeProApp extends StatelessWidget {
  const SmartHomeProApp({super.key, required this.settings});

  final AppSettingsController settings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (_, __) {
        return MaterialApp(
          title: 'SmartHome Pro',
          debugShowCheckedModeBanner: false,
          locale: settings.locale,
          supportedLocales: const [Locale('en'), Locale('bn')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          themeMode: settings.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorSchemeSeed: const Color(0xFF1E88E5),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorSchemeSeed: const Color(0xFF38BDF8),
          ),
          home: MultiDeviceListScreen(settings: settings),
        );
      },
    );
  }
}

class MultiDeviceListScreen extends StatefulWidget {
  const MultiDeviceListScreen({super.key, required this.settings});

  final AppSettingsController settings;

  @override
  State<MultiDeviceListScreen> createState() => _MultiDeviceListScreenState();
}

class _MultiDeviceListScreenState extends State<MultiDeviceListScreen> {
  static const _savedDevicesKey = 'saved_devices';

  bool _loading = true;
  String? _loadError;
  List<SavedDevice> _devices = <SavedDevice>[];

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _loadSavedDevices();
  }

  Future<void> _requestPermissions() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }

    try {
      await <Permission>[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
    } catch (_) {
      // Keep app usable even if a permission package call fails on unsupported platforms.
    }
  }

  Future<void> _loadSavedDevices() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? rawList = prefs.getString(_savedDevicesKey);
      if (rawList == null || rawList.isEmpty) {
        setState(() {
          _devices = <SavedDevice>[];
          _loading = false;
        });
        return;
      }

      final decoded = jsonDecode(rawList);
      if (decoded is! List) {
        throw const FormatException('Invalid saved device payload');
      }

      final parsed = decoded
          .whereType<Map<String, dynamic>>()
          .map(SavedDevice.fromJson)
          .where((d) => d.deviceId.isNotEmpty)
          .toList(growable: false);

      setState(() {
        _devices = parsed;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _loadError = 'load_failed';
        _loading = false;
      });
    }
  }

  Future<void> _persistDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_devices.map((e) => e.toJson()).toList());
    await prefs.setString(_savedDevicesKey, encoded);
  }

  Future<void> _addOrUpdateDevice(SavedDevice newDevice) async {
    setState(() {
      final index = _devices.indexWhere((d) => d.deviceId == newDevice.deviceId);
      if (index == -1) {
        _devices.add(newDevice);
      } else {
        _devices[index] = newDevice;
      }
    });
    await _persistDevices();
  }

  Future<void> _deleteDevice(String deviceId) async {
    setState(() {
      _devices.removeWhere((d) => d.deviceId == deviceId);
    });
    await _persistDevices();
  }

  Future<void> _openDeviceForm({SavedDevice? existing, String? prefilledId}) async {
    final l10n = AppLocalizations.of(context)!;
    final nameController = TextEditingController(text: existing?.name ?? 'Living Room');
    final idController = TextEditingController(text: existing?.deviceId ?? prefilledId ?? 'SHN-');
    final pinController = TextEditingController(text: existing?.pin ?? '123456');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  existing == null ? l10n.addDevice : l10n.editDevice,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: l10n.deviceName,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: idController,
                  textCapitalization: TextCapitalization.characters,
                  enabled: existing == null,
                  decoration: InputDecoration(
                    labelText: l10n.deviceId,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pinController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.devicePin,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(l10n.cancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          final id = idController.text.trim().toUpperCase();
                          final name = nameController.text.trim();
                          final pin = pinController.text.trim();

                          if (id.isEmpty || name.isEmpty || pin.isEmpty) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l10n.invalidInput)),
                            );
                            return;
                          }

                          await _addOrUpdateDevice(
                            SavedDevice(deviceId: id, name: name, pin: pin),
                          );

                          if (!mounted) return;
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(l10n.saved)));
                          Navigator.pop(context);
                        },
                        child: Text(l10n.save),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showBleScannerModal() async {
    final l10n = AppLocalizations.of(context)!;

    if (!kIsWeb) {
      try {
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));
      } catch (_) {
        // ignore scanner start errors; the sheet still opens with fallback state.
      }
    }

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        if (kIsWeb) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(height: 160, child: Center(child: Text(l10n.bleUnavailable))),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 380,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(l10n.scanNearby, style: Theme.of(context).textTheme.titleMedium),
                    IconButton(
                      tooltip: l10n.scanBle,
                      onPressed: () {
                        FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
                      },
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: StreamBuilder<List<ScanResult>>(
                    stream: FlutterBluePlus.scanResults,
                    builder: (context, snapshot) {
                      final results = (snapshot.data ?? <ScanResult>[]).where((r) {
                        final name = r.device.platformName.trim();
                        return name.isNotEmpty && (name.startsWith('SHN-') || name.length >= 4);
                      }).toList();

                      if (results.isEmpty) {
                        return Center(child: Text(l10n.scanning));
                      }

                      return ListView.separated(
                        itemCount: results.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final result = results[index];
                          final name = result.device.platformName;
                          return ListTile(
                            leading: const Icon(Icons.bluetooth),
                            title: Text(name),
                            subtitle: Text('RSSI ${result.rssi} dBm'),
                            trailing: FilledButton(
                              onPressed: () {
                                FlutterBluePlus.stopScan();
                                Navigator.pop(context);
                                _openDeviceForm(prefilledId: name);
                              },
                              child: Text(l10n.select),
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
      },
    );
  }

  Future<void> _showAppSettingsModal() async {
    final l10n = AppLocalizations.of(context)!;

    ThemeMode localThemeMode = widget.settings.themeMode;
    Locale localLocale = widget.settings.locale;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.settings, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<Locale>(
                    initialValue: localLocale,
                    decoration: InputDecoration(
                      labelText: l10n.language,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(value: const Locale('en'), child: Text(l10n.english)),
                      DropdownMenuItem(value: const Locale('bn'), child: Text(l10n.bangla)),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setStateModal(() => localLocale = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ThemeMode>(
                    initialValue: localThemeMode,
                    decoration: InputDecoration(
                      labelText: l10n.theme,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: ThemeMode.system,
                        child: Text(l10n.themeSystem),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.light,
                        child: Text(l10n.themeLight),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.dark,
                        child: Text(l10n.themeDark),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setStateModal(() => localThemeMode = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        await widget.settings.updateLocale(localLocale);
                        await widget.settings.updateThemeMode(localThemeMode);
                        if (!mounted) return;
                        Navigator.pop(context);
                      },
                      child: Text(l10n.save),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.devicesTitle),
        actions: [
          IconButton(
            tooltip: l10n.scanBle,
            onPressed: _showBleScannerModal,
            icon: const Icon(Icons.bluetooth_searching),
          ),
          IconButton(
            tooltip: l10n.settings,
            onPressed: _showAppSettingsModal,
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: Builder(
          builder: (_) {
            if (_loading) {
              return Center(child: Text(l10n.loading));
            }
            if (_loadError != null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.errorLoadingDevices),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _loadSavedDevices, child: Text(l10n.retry)),
                    ],
                  ),
                ),
              );
            }
            if (_devices.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.home_outlined,
                        size: 72,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(l10n.noDevicesTitle, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(
                        l10n.noDevicesMessage,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _showBleScannerModal,
                        icon: const Icon(Icons.bluetooth_searching),
                        label: Text(l10n.scanNearby),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _devices.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final device = _devices[index];
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                      child: Icon(Icons.memory,
                          color: Theme.of(context).colorScheme.onPrimaryContainer),
                    ),
                    title: Text(device.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${l10n.deviceId}: ${device.deviceId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') {
                          _openDeviceForm(existing: device);
                        } else if (value == 'delete') {
                          _deleteDevice(device.deviceId);
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'edit', child: Text(l10n.editDevice)),
                        PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
                      ],
                    ),
                    onTap: () {
                      Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DeviceDashboardScreen(device: device),
                        ),
                      );
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openDeviceForm,
        icon: const Icon(Icons.add),
        label: Text(l10n.addDevice),
      ),
    );
  }
}

enum ConnectionPreference { auto, ble, mqtt }

class DeviceDashboardScreen extends StatefulWidget {
  const DeviceDashboardScreen({super.key, required this.device});

  final SavedDevice device;

  @override
  State<DeviceDashboardScreen> createState() => _DeviceDashboardScreenState();
}

class _DeviceDashboardScreenState extends State<DeviceDashboardScreen>
    with WidgetsBindingObserver {
  bool _bleConnected = false;
  bool _mqttConnected = false;
  bool _deviceOnlineMqtt = false;
  bool _lightState = false;
  bool _fanState = false;

  String _lastSyncSource = '--';
  String _authStatus = '--';

  ConnectionPreference _connectionPreference = ConnectionPreference.auto;

  BluetoothDevice? _bleDevice;
  BluetoothCharacteristic? _bleCommandCharacteristic;

  StreamSubscription<List<ScanResult>>? _bleScanSubscription;
  StreamSubscription<BluetoothConnectionState>? _bleConnectionSubscription;
  StreamSubscription<List<int>>? _bleNotifySubscription;

  MqttServerClient? _mqttClient;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage?>>>? _mqttSubscription;

  Timer? _clockTimer;
  Timer? _mqttReconnectTimer;
  DateTime _now = DateTime.now();

  Map<String, dynamic> _deviceInfo = <String, dynamic>{};
  Map<String, dynamic> _telemetry = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authStatus = AppLocalizations.of(context)?.waitingConnections ?? '--';
    _startClock();
    _initConnections();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initConnections();
      _sendCommand({'cmd': 'get_status'});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _mqttReconnectTimer?.cancel();
    _bleScanSubscription?.cancel();
    _bleConnectionSubscription?.cancel();
    _bleNotifySubscription?.cancel();
    _mqttSubscription?.cancel();
    _bleDevice?.disconnect();
    _mqttClient?.disconnect();
    super.dispose();
  }

  void _startClock() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  void _initConnections() {
    _connectBle();
    _connectMqtt();
  }

  Future<void> _connectBle() async {
    if (kIsWeb) return;
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
      await _bleScanSubscription?.cancel();
      _bleScanSubscription = FlutterBluePlus.scanResults.listen((results) async {
        for (final result in results) {
          if (result.device.platformName.trim() != widget.device.deviceId) continue;

          await FlutterBluePlus.stopScan();
          _bleDevice = result.device;

          await _bleConnectionSubscription?.cancel();
          _bleConnectionSubscription = _bleDevice!.connectionState.listen((state) {
            if (!mounted) return;
            setState(() {
              _bleConnected = state == BluetoothConnectionState.connected;
            });
          });

          await _bleDevice!.connect(
            license: License.free,
            mtu: 512,
            autoConnect: false,
          );

          final services = await _bleDevice!.discoverServices();
          for (final service in services) {
            if (service.uuid.toString().toLowerCase() != kServiceUuid) continue;

            for (final characteristic in service.characteristics) {
              final uuid = characteristic.uuid.toString().toLowerCase();
              if (uuid == kCharCmdUuid) {
                _bleCommandCharacteristic = characteristic;
              } else if (uuid == kCharStateUuid) {
                await characteristic.setNotifyValue(true);
                await _bleNotifySubscription?.cancel();
                _bleNotifySubscription = characteristic.onValueReceived.listen((value) {
                  _handleIncomingPayload(utf8.decode(value, allowMalformed: true), 'BLE');
                });
              }
            }
          }

          _sendCommand({'cmd': 'login'});
          return;
        }
      });
    } catch (_) {
      // BLE is optional path; MQTT still works.
    }
  }

  Future<void> _connectMqtt() async {
    final clientId =
        'FlutterApp-${widget.device.deviceId}-${Random().nextInt(100000)}';
    final client = MqttServerClient(kMqttBroker, clientId)
      ..port = kMqttPort
      ..keepAlivePeriod = 30
      ..autoReconnect = true
      ..resubscribeOnAutoReconnect = true;

    client.onConnected = () {
      if (!mounted) return;

      setState(() {
        _mqttConnected = true;
      });

      final stateTopic = 'iot/smarthome/${widget.device.deviceId}/state';
      final availabilityTopic = 'iot/smarthome/${widget.device.deviceId}/availability';

      client.subscribe(stateTopic, MqttQos.atLeastOnce);
      client.subscribe(availabilityTopic, MqttQos.atLeastOnce);
      _mqttSubscription?.cancel();
      _mqttSubscription = client.updates?.listen((messages) {
        if (messages.isEmpty) return;
        final message = messages.first;
        if (message.payload is! MqttPublishMessage) return;

        final payload = MqttPublishPayload.bytesToStringAsString(
          (message.payload as MqttPublishMessage).payload.message,
        );

        if (message.topic.endsWith('/availability')) {
          if (!mounted) return;
          setState(() {
            _deviceOnlineMqtt = payload.trim().toUpperCase() == 'ONLINE';
          });
          return;
        }

        _handleIncomingPayload(payload, 'MQTT');
      });

      _sendCommand({'cmd': 'login'});
    };

    client.onDisconnected = () {
      if (!mounted) return;
      setState(() {
        _mqttConnected = false;
      });
      _scheduleMqttReconnect();
    };

    client.pongCallback = () {
      if (!mounted) return;
      if (!_mqttConnected) {
        setState(() {
          _mqttConnected = true;
        });
      }
    };

    _mqttClient = client;

    try {
      await client.connect();
    } catch (_) {
      client.disconnect();
      _scheduleMqttReconnect();
    }
  }

  void _scheduleMqttReconnect() {
    _mqttReconnectTimer?.cancel();
    _mqttReconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || _mqttConnected) return;
      _connectMqtt();
    });
  }

  Future<void> _sendCommand(Map<String, dynamic> payload) async {
    payload['pin'] = widget.device.pin;
    final jsonPayload = jsonEncode(payload);

    final canUseBle = _connectionPreference == ConnectionPreference.ble ||
        (_connectionPreference == ConnectionPreference.auto &&
            _bleConnected &&
            _bleCommandCharacteristic != null);

    if (canUseBle && _bleConnected && _bleCommandCharacteristic != null) {
      try {
        await _bleCommandCharacteristic!.write(
          utf8.encode(jsonPayload),
          withoutResponse: false,
        );
        return;
      } catch (_) {
        // If BLE send fails, continue with MQTT fallback.
      }
    }

    final canUseMqtt = _connectionPreference == ConnectionPreference.mqtt ||
        _connectionPreference == ConnectionPreference.auto;

    if (canUseMqtt && _mqttConnected && _mqttClient != null) {
      final commandTopic = 'iot/smarthome/${widget.device.deviceId}/cmd';
      final builder = MqttClientPayloadBuilder()..addString(jsonPayload);
      _mqttClient!.publishMessage(
        commandTopic,
        MqttQos.atLeastOnce,
        builder.payload!,
        retain: false,
      );
      return;
    }

    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.waitingConnections)),
    );
  }

  void _handleIncomingPayload(String payload, String transport) {
    final l10n = AppLocalizations.of(context)!;
    final parsed = parseDeviceMessage(payload);

    if (parsed.isMalformed) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.invalidJson)),
      );
      return;
    }

    if (parsed.message != null && parsed.message!.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${parsed.status ?? 'INFO'}: ${parsed.message}')),
      );
    }

    if (parsed.isUnauthorized) {
      if (!mounted) return;
      setState(() {
        _authStatus = l10n.authFailed;
      });
      return;
    }

    final state = parsed.state;
    if (state == null) return;

    if (!mounted) return;
    setState(() {
      _authStatus = l10n.authenticated;
      _lightState = state['light'] == true;
      _fanState = state['fan'] == true;
      _lastSyncSource = '$transport (${parsed.source ?? 'SYNC'})';
      _deviceOnlineMqtt = parsed.online ?? _deviceOnlineMqtt;
      if (parsed.info != null) _deviceInfo = parsed.info!;
      if (parsed.telemetry != null) _telemetry = parsed.telemetry!;
    });
  }

  Future<void> _showProvisioningSheet() async {
    final l10n = AppLocalizations.of(context)!;
    final ssidController = TextEditingController();
    final passController = TextEditingController();
    final pinController = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.provisioning, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                Text(l10n.wifiSection, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: ssidController,
                  decoration: InputDecoration(
                    labelText: l10n.wifiSsid,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.wifiPassword,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () {
                    _sendCommand({
                      'cmd': 'set_wifi',
                      'ssid': ssidController.text.trim(),
                      'pass': passController.text.trim(),
                    });
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.wifi),
                  label: Text(l10n.sendWifi),
                ),
                const Divider(height: 24),
                Text(l10n.pinSection, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: pinController,
                        decoration: InputDecoration(
                          labelText: l10n.newPin,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        final pin = pinController.text.trim();
                        if (pin.length < 4) return;
                        _sendCommand({'cmd': 'set_pin', 'new_pin': pin});
                        widget.device.pin = pin;
                        Navigator.pop(context);
                      },
                      child: Text(l10n.updatePin),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        _sendCommand({'cmd': 'reboot'});
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.restart_alt),
                      label: Text(l10n.reboot),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        _sendCommand({'cmd': 'factory_reset'});
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.delete_forever),
                      label: Text(l10n.factoryReset),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formattedClock(BuildContext context) {
    final localeCode = Localizations.localeOf(context).languageCode;
    final formatter = DateFormat.yMMMMEEEEd(localeCode).add_jms();
    return formatter.format(_now);
  }

  String _activeRouteLabel(AppLocalizations l10n) {
    final usesBle = _connectionPreference == ConnectionPreference.ble ||
        (_connectionPreference == ConnectionPreference.auto && _bleConnected);
    if (usesBle) return l10n.routeBle;
    if (_mqttConnected) return l10n.routeMqtt;
    return l10n.routeDisconnected;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isOffline = !_bleConnected && !(_mqttConnected && _deviceOnlineMqtt);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.device.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(widget.device.deviceId, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l10n.refresh,
            onPressed: () => _sendCommand({'cmd': 'get_status'}),
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: l10n.settings,
            onPressed: _showProvisioningSheet,
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isOffline)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(l10n.offlineBanner),
                  ),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          _statusChip(l10n.bleReady, l10n.bleAway, _bleConnected, Icons.bluetooth),
                          _statusChip(
                            l10n.cloudOnline,
                            l10n.cloudOffline,
                            _mqttConnected && _deviceOnlineMqtt,
                            Icons.cloud_done,
                          ),
                          Chip(
                            label: Text(_authStatus),
                            avatar: Icon(
                              _authStatus == l10n.authenticated
                                  ? Icons.verified_user
                                  : Icons.info_outline,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${l10n.activeRoute}: ${_activeRouteLabel(l10n)}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          DropdownButton<ConnectionPreference>(
                            value: _connectionPreference,
                            items: [
                              DropdownMenuItem(
                                value: ConnectionPreference.auto,
                                child: Text(l10n.routeAuto),
                              ),
                              DropdownMenuItem(
                                value: ConnectionPreference.ble,
                                child: Text(l10n.routeBleOnly),
                              ),
                              DropdownMenuItem(
                                value: ConnectionPreference.mqtt,
                                child: Text(l10n.routeCloudOnly),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _connectionPreference = value);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.access_time),
                  title: Text(l10n.clockTitle),
                  subtitle: Text(_formattedClock(context)),
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 580;
                  final cardWidth = isWide ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: cardWidth,
                        child: _applianceCard(
                          title: l10n.light,
                          subtitle: 'IN1',
                          isOn: _lightState,
                          icon: Icons.lightbulb,
                          color: Colors.amber,
                          onChanged: (value) {
                            setState(() => _lightState = value);
                            _sendCommand({'cmd': 'control', 'light': value});
                          },
                          l10n: l10n,
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _applianceCard(
                          title: l10n.fan,
                          subtitle: 'IN2',
                          isOn: _fanState,
                          icon: Icons.mode_fan_off,
                          color: Colors.lightBlue,
                          onChanged: (value) {
                            setState(() => _fanState = value);
                            _sendCommand({'cmd': 'control', 'fan': value});
                          },
                          l10n: l10n,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              _infoCard(
                title: l10n.telemetry,
                rows: [
                  _kv(l10n.lastSync, _lastSyncSource),
                  _kv(l10n.wifiSignal, '${_telemetry['wifi_rssi'] ?? '--'} dBm'),
                  _kv(l10n.localIp, '${_telemetry['ip'] ?? '--'}'),
                  _kv(l10n.uptime, '${_telemetry['uptime_sec'] ?? '--'} s'),
                  _kv(l10n.freeHeap, '${_telemetry['free_heap'] ?? '--'} bytes'),
                ],
              ),
              const SizedBox(height: 12),
              _infoCard(
                title: l10n.deviceInfo,
                rows: [
                  _kv(l10n.deviceId, widget.device.deviceId),
                  _kv(l10n.manufacturer, '${_deviceInfo['manufacturer'] ?? 'SmartHome'}'),
                  _kv(l10n.model, '${_deviceInfo['model'] ?? '--'}'),
                  _kv(l10n.firmware, '${_deviceInfo['fw_version'] ?? '--'}'),
                  _kv(l10n.hardware, '${_deviceInfo['hw_version'] ?? '--'}'),
                  _kv(l10n.mfgDate, '${_deviceInfo['mfg_date'] ?? '--'}'),
                  _kv(l10n.releaseDate, '${_deviceInfo['release_date'] ?? '--'}'),
                  _kv(l10n.buildTime, '${_deviceInfo['build_time'] ?? '--'}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String active, String inactive, bool isActive, IconData icon) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(isActive ? active : inactive),
      backgroundColor: isActive
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }

  Widget _applianceCard({
    required String title,
    required String subtitle,
    required bool isOn,
    required IconData icon,
    required Color color,
    required ValueChanged<bool> onChanged,
    required AppLocalizations l10n,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: isOn ? color : Theme.of(context).colorScheme.outline),
                Switch(value: isOn, onChanged: onChanged),
              ],
            ),
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            Text(
              '$subtitle • ${isOn ? l10n.on : l10n.off}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard({required String title, required List<Widget> rows}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...rows,
          ],
        ),
      ),
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(key)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
