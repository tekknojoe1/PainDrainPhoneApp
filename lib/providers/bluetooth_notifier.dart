import 'dart:async';
import 'dart:collection';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:pain_drain_mobile_app/models/device_state.dart';
import 'package:pain_drain_mobile_app/providers/temperature_notifier.dart';
import 'package:pain_drain_mobile_app/providers/tens_notifier.dart';
import 'package:pain_drain_mobile_app/providers/vibration_notifier.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/preset.dart';
import '../utils/go_router.dart';

part 'bluetooth_notifier.g.dart';

@Riverpod(keepAlive: true)
class BluetoothNotifier extends _$BluetoothNotifier {
  // Private variables for internal logic
  final Queue<List<int>> _queue = Queue<List<int>>();
  final String _customServiceUUID = "3bf00c21-d291-4688-b8e9-5a379e3d9874";
  final String _customCharacteristicUUID = "93c836a2-695a-42cc-95ac-1afa0eef6b0a";
  final String _batteryServiceUUID = "180f";
  final String _batteryCharacteristicUUID = "2a19";
  final String _characteristicConfigurationUUID = "2902";

  late BluetoothDescriptor _customConfigurationDescriptor;

  late BluetoothService _customService;
  late BluetoothService _batteryService;
  late BluetoothCharacteristic _customCharacteristic;
  late BluetoothCharacteristic _batteryCharacteristic;
  BluetoothDevice? _myConnectedDevice;
  late List<BluetoothService> _services;

  @override
  DeviceState build() {
    return const DeviceState();
  }

  /// Scans for devices and updates the state with scan results.
  Future<void> scanForDevices() async {
    print("Scanning for devices");
    //List<ScanResult> results = [];
    final scanSubscription = FlutterBluePlus.onScanResults.listen((r) {
        // Update state as soon as scan results are received.
        state = state.copyWith(scanResults: r.toList());
        print("current state ${state.scanResults}");
        //results = r.toList();
      },
      onError: (e) => print("Scan error: $e"),
    );

    FlutterBluePlus.cancelWhenScanComplete(scanSubscription);

    await FlutterBluePlus.startScan(
      withNames: ["PainDrain"],
      timeout: const Duration(seconds: 5),
    );

    // Wait for scanning to stop
    await FlutterBluePlus.isScanning.where((val) => val == false).first;

    if (state.scanResults.isNotEmpty) {
      print("Scan results not empty");
    } else {
      print("Scan results empty");
    }

    // Update the state with scan results
    //state = state.copyWith(scanResults: results);
  }

  /// Connects to a Bluetooth device and updates the state.
  Future<bool> connectDevice(BluetoothDevice device) async {
    bool success = false;
    try {
      _myConnectedDevice = device;
      await device.connect();
      print("After connection");

      // Listen for connection state changes.
      final connectionSubscription =
      device.connectionState.listen((BluetoothConnectionState connState) async {
        if (connState == BluetoothConnectionState.disconnected) {
          // Here you might navigate to a disconnection screen or update UI.
          // For example, update the state:
          routes.go('/');
          state = state.copyWith(isConnected: false, connectedDevice: null);
          print("Device disconnected");
          // (In your old code, you used Get.to(); adjust as needed.)
        } else if (connState == BluetoothConnectionState.connected) {
          success = true;
        }
      });

      device.cancelWhenDisconnected(connectionSubscription, delayed: true, next: true);
      await discoverServices(device);

      // Setup notifications and listeners.
      await setupListeners(device);

      // Finally, update the state
      state = state.copyWith(isConnected: true, connectedDevice: device);
      success = true;
    } catch (e) {
      success = false;
      print("Error connecting: $e");
    }
    return success;
  }

  /// Disconnects the currently connected device.
  Future<bool> disconnectDevice() async {
    if (_myConnectedDevice != null) {
      try {
        await _myConnectedDevice!.disconnect();
        state = state.copyWith(isConnected: false, connectedDevice: null);
        return true;
      } catch (e) {
        print("Couldn't disconnect: $e");
      }
    }
    return false;
  }

  /// Discovers services and characteristics on the connected device.
  Future<void> discoverServices(BluetoothDevice connectedDevice) async {
    _services = await connectedDevice.discoverServices();

    // Look for custom and battery services.
    for (BluetoothService service in _services) {
      if (service.uuid.toString() == _customServiceUUID) {
        print("Custom service found");
        _customService = service;
      } else if (service.uuid.toString() == _batteryServiceUUID) {
        _batteryService = service;
      }
    }

    // Look for characteristics in the custom service.
    for (BluetoothCharacteristic characteristic in _customService.characteristics) {
      if (characteristic.uuid.toString() == _customCharacteristicUUID) {
        print("Custom characteristic found");
        _customCharacteristic = characteristic;
        // Find the configuration descriptor.
        for (BluetoothDescriptor descriptor in _customCharacteristic.descriptors) {
          if (descriptor.uuid.toString() == _characteristicConfigurationUUID) {
            _customConfigurationDescriptor = descriptor;
          }
        }
      }
    }

    // Look for the battery characteristic.
    for (BluetoothCharacteristic characteristic in _batteryService.characteristics) {
      if (characteristic.uuid.toString() == _batteryCharacteristicUUID) {
        print("Battery characteristic found: $characteristic");
        _batteryCharacteristic = characteristic;
      }
    }
  }

  /// Writes data to the device based on the provided stimulus.
  Future<void> writeToDevice(String stimulus, List<int> hexValues) async {
    switch (stimulus) {
      case "tens":
        await _customCharacteristic.write(hexValues);
        print("tens");
        break;
      case "temperature":
        await _customCharacteristic.write(hexValues);
        print("temperature");
        break;
      case "vibration":
        print('vibration $hexValues');
        await _customCharacteristic.write(hexValues);
        print("vibration");
        break;
      case "register":
        print('register $hexValues');
        await _customCharacteristic.write(hexValues);
        print("register");
        break;
      case "notifications":
        await _customCharacteristic.write(hexValues);
        break;
      case "B":
        await _customCharacteristic.write(hexValues);
        break;
      default:
        print("error: unknown stimulus");
        break;
    }
  }

  /// Converts a command string to hex values, queues it, and writes to the device.
  Future<void> newWriteToDevice(String command) async {
    try {
      List<int> hexValues = stringToHexList(command);
      _queue.add(hexValues);

      while (_queue.isNotEmpty) {
        print("Elements in queue: ${_queue.length}");
        List<int> currentHexValues = _queue.removeFirst();
        if (currentHexValues.length > 20) {
          print("Big data");
          await _customCharacteristic.write(currentHexValues, allowLongWrite: true);
        } else {
          print("Not big data");
          await _customCharacteristic.write(currentHexValues);
        }
      }
    } catch (e) {
      print("Error in newWriteToDevice: $e");
    }
  }

  Future<void> uploadPresetToDevice(Preset preset) async {
    print("Uploading");
    int currentChannel = preset.tens.currentChannel;
    String presetNumber = preset.id.toString();
    String intensity = preset.tens.intensity.toString();
    String mode = preset.tens.channels[currentChannel - 1].mode.toString();
    String playButton = preset.tens.channels[currentChannel - 1].isPlaying ? '1' : '0';
    String phase = preset.tens.phase.toString();
    String command = 'p $presetNumber T $intensity $mode $playButton ${currentChannel.toString()} $phase';
    print(command);
    await newWriteToDevice(command);
    String temp = preset.temperature.temperature.toString();
    command = "p $presetNumber t $temp";
    print(command);

    await newWriteToDevice(command);
    String frequency = preset.vibration.frequency.toString();
    command = "p $presetNumber v $frequency";
    print(command);

    await newWriteToDevice(command);
  }

  /// Debug print for received string values.
  void devDebugPrint(String readString) {
    if (readString.isEmpty) return;
    if (readString[0] == "T") {
      // Replace with your own logic or update state as needed.
      print("Debug Tens: $readString");
    } else if (readString[0] == "v") {
      print("Debug Vibration: $readString");
    } else if (readString[0] == "t") {
      print("Debug Temperature: $readString");
    } else {
      print("No valid value in debug print");
    }
  }

  /// Builds a command string for the given stimulus.
  ///
  /// Note: This version uses placeholder values. Adjust as needed,
  /// especially if you have dependencies (like a stimulus controller) to consult.
  String getCommand(String stimulus) {
    String command = "";
    switch (stimulus) {
      case "tens":
      // Use placeholder values; replace with your actual logic.
        int currentChannel = ref.read(tensNotifierProvider).currentChannel;
        String intensity = ref.read(tensNotifierProvider).intensity.toString();
        String mode = ref.read(tensNotifierProvider).channels[currentChannel - 1].mode.toString();
        String playButton = ref.read(tensNotifierProvider).channels[currentChannel - 1].isPlaying ? '1' : '0';
        String phase = ref.read(tensNotifierProvider).phase.toString();
        command = "T $intensity $mode $playButton ${currentChannel.toString()} $phase";
        print("tens command: $command");
        break;
      case "temperature":
        String temp = ref.read(temperatureNotifierProvider).temperature.toString();
        command = "t $temp";
        print("temperature command: $command");
        break;
      case "vibration":
        String frequency = ref.read(vibrationNotifierProvider).frequency.toString();
        command = "v $frequency";
        print("vibration command: $command");
        break;
      default:
        print("error: Stimulus doesn't exist. Use 'tens', 'vibration', or 'temperature'");
        break;
    }
    print("Sending command: $command");
    // For debugging, override command if needed:
    //command = "p 1 t -100";
    return command;
  }

  /// Reads data from the device, trimming data after a null terminator.
  Future<List<int>> readFromDevice() async {
    try {
      List<int> rspHexValues = await _customCharacteristic.read();
      if (rspHexValues.contains(0)) {
        rspHexValues = rspHexValues.sublist(0, rspHexValues.indexOf(0));
      }
      return rspHexValues;
    } catch (e) {
      print("Error during readFromDevice: $e");
      rethrow;
    }
  }

  /// Converts a string into a list of its hex values.
  List<int> stringToHexList(String input) {
    List<int> hexList = [];
    for (int i = 0; i < input.length; i++) {
      hexList.add(input.codeUnitAt(i));
    }
    return hexList;
  }

  /// Converts a list of hex values back into a string.
  String hexToString(List<int> list) {
    String asciiString = "";
    for (int hexValue in list) {
      asciiString += String.fromCharCode(hexValue);
    }
    return asciiString;
  }

  /// Sets up notifications and listeners on the custom characteristic.
  Future<void> setupListeners(BluetoothDevice device) async {
    final customCharacteristicSubscription = _customCharacteristic.onValueReceived.listen((value) {
      print("Characteristic received: $value");
      String read = hexToString(value);
      print("Received string: $read");
      devDebugPrint(read);
      if (read == "charge") {
        // Insert logic to handle charging (for example, update state)
        print("Device is charging");
      } else if (read == "no charge" || read == "normal") {
        state = state.copyWith(isCharging: false);
      }
    });

    // Cancel the subscription when the device disconnects.
    device.cancelWhenDisconnected(customCharacteristicSubscription);

    // // Enable notifications on the characteristic.
    // ✅ Check if notifications or indications are supported before enabling them
    if (_customCharacteristic.properties.notify || _customCharacteristic.properties.indicate) {
      try {
        await _customCharacteristic.setNotifyValue(true);
        print("✅ Notifications enabled successfully.");
      } catch (e) {
        print("⚠️ Error enabling notifications: $e");
      }
    } else {
      print("⚠️ Characteristic does not support notifications or indications.");
    }
  }
}
