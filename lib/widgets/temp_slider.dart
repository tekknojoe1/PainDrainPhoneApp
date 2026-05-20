import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_xlider/flutter_xlider.dart';
import 'package:pain_drain_mobile_app/providers/bluetooth_notifier.dart';
import 'package:pain_drain_mobile_app/providers/temperature_notifier.dart';

class TempSlider extends ConsumerStatefulWidget {
  //double currentValue;

  TempSlider({Key? key}) : super(key: key);

  @override
  ConsumerState<TempSlider> createState() => _TempSliderState();
}

class _TempSliderState extends ConsumerState<TempSlider> {
  Timer? _throttleTimer; // Timer to throttle the updates
  double? _lastSentValue; // To keep track of the last sent value
  //final Stimulus _stimController = Get.find();
  //final Bluetooth _bleController = Get.find();

  final double _minValue = -100;
  final double _maxValue = 100;
  Color trackBarColor = Colors.grey;
  Color thumbSlider = Colors.grey;

  @override
  Widget build(BuildContext context) {
    final temp = ref.watch(temperatureNotifierProvider);
    final deviceStatus = ref.watch(bluetoothNotifierProvider);

    if(temp.temperature < 0){
      trackBarColor = Colors.blue;
      thumbSlider = Colors.blue;
    }
    else if(temp.temperature > 0) {
      trackBarColor = Colors.red;
      thumbSlider = Colors.red;
    }
    else {
      trackBarColor = Colors.grey;
      thumbSlider = Colors.grey;
    }
    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: FlutterSlider(
        values: [temp.temperature.toDouble()],
        max: _maxValue,
        min: _minValue,
        disabled: deviceStatus.isCharging,
        centeredOrigin: true,
        handlerWidth: 45.0,
        handlerHeight: 45.0,
        touchSize: 5,
        trackBar: FlutterSliderTrackBar(
            activeTrackBar: BoxDecoration(
                color: trackBarColor,
                borderRadius: BorderRadius.circular(5.0)
            ),
            activeTrackBarHeight: 10.0,
            inactiveTrackBarHeight: 8.0,
            inactiveTrackBar: BoxDecoration(
                color: Colors.grey.withOpacity(.4),
                borderRadius: BorderRadius.circular(5.0)
            ),
            inactiveDisabledTrackBarColor: Colors.grey
        ),
        handler: FlutterSliderHandler(
            child: Text("${temp.temperature.toInt()}%", style: const TextStyle(color: Colors.white)),
            decoration: BoxDecoration(
                color: thumbSlider,
                borderRadius: BorderRadius.circular(50.0)
            ),
            disabled: false
        ),
        tooltip: FlutterSliderTooltip(
            disabled: true
        ),
        onDragging: (handlerIndex, lowerValue, upperValue) {
          // Changes the track color
          if(lowerValue == 0) {
            thumbSlider = Colors.grey;
          }
          else if (lowerValue < 0) {
            trackBarColor = Colors.blueAccent;
            thumbSlider = Colors.blueAccent;
          }
          else {
            trackBarColor = Colors.red;
            thumbSlider = Colors.red;
          }
          // Throttle updates to avoid sending too many values
          if (_throttleTimer == null || !_throttleTimer!.isActive) {
            // Check if the value is the same as the last sent value to avoid redundancy
            if (_lastSentValue == null || _lastSentValue != lowerValue) {
              ref.read(temperatureNotifierProvider.notifier).updateTemperature(temp: lowerValue.toInt());
              //_stimController.setStimulus("temp", lowerValue);
              // setState(() {
              //   widget.currentValue = _stimController.getStimulus("temp");
              // });

              // Set the last sent value
              _lastSentValue = lowerValue;

              // Optional: Send the command if needed in real time
              String command = ref.read(bluetoothNotifierProvider.notifier).getCommand("temperature");
              ref.read(bluetoothNotifierProvider.notifier).newWriteToDevice(command);
            }

            // Set the throttle timer to delay the next update
            _throttleTimer = Timer(const Duration(milliseconds: 100), () {
              // This allows updates after the throttle duration has passed
            });
          }
        },
        onDragCompleted: (handlerIndex, lowerValue, upperValue) {
          // Send the final value once dragging is completed
          ref.read(temperatureNotifierProvider.notifier).updateTemperature(temp: lowerValue.toInt());
          // _stimController.setStimulus("temp", lowerValue);
          // setState(() {
          //   widget.currentValue = _stimController.getStimulus("temp");
          // });
          String command = ref.read(bluetoothNotifierProvider.notifier).getCommand("temperature");
          ref.read(bluetoothNotifierProvider.notifier).newWriteToDevice(command);
          _lastSentValue = null; // Reset the last sent value for the next drag event
        },
      )
      );
  }
}
