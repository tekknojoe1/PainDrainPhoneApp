
import 'dart:async';

import 'package:animated_icon/animate_icon.dart';
import 'package:animated_icon/animate_icons.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:pain_drain_mobile_app/main.dart';
import 'package:pain_drain_mobile_app/models/temperature.dart';
import 'package:pain_drain_mobile_app/models/vibration.dart';
import 'package:pain_drain_mobile_app/providers/preset_list_notifier.dart';
import 'package:pain_drain_mobile_app/providers/temperature_notifier.dart';
import 'package:pain_drain_mobile_app/providers/tens_notifier.dart';
import 'package:pain_drain_mobile_app/providers/vibration_notifier.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pain_drain_mobile_app/screens/home/local_widgets/onboarding.dart';
import 'package:pain_drain_mobile_app/widgets/custom_text_field.dart';
import 'package:pain_drain_mobile_app/widgets/drop_down_button.dart';
import 'package:pain_drain_mobile_app/widgets/tens_summary.dart';
import 'package:pain_drain_mobile_app/widgets/vibration_summary.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import '../../models/preset.dart';
import '../../models/tens.dart';
import '../../providers/bluetooth_notifier.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_feedback.dart';
import '../../widgets/temperature_summary.dart';

List<String> presetOptions = ['Preset 1', 'Preset 2', 'Preset 3'];



class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  bool isAddingItem = false; // Track whether we are in "add" mode
  bool isLoading = false;
  double batteryLevel = 100;
  bool isCharging = false;
  bool uploadingPreset = false;
  Icon batteryIcon = const Icon(Icons.battery_full, color: Colors.green,);
  Color color = Colors.green;
  String currentOption = presetOptions[0];
  String uploadToDeviceString = "Uploading preset to device...";
  late AnimationController _controller;
  String _appVersion = '';
  int? _selectedIndex; // Track which button is selected
  int? _loadingIndex; // Track which button is showing a progress indicator
  double _progress = 0.0; // Track progress percentage
  Timer? _timer; // Timer for tracking hold duration

  decrementBattery() async {
    for(int i = 0; i < 100; i++){
      print("battery Level $batteryLevel");
      await Future.delayed(const Duration(milliseconds: 100));
      setState(() => batteryLevel--);
      if(batteryLevel == 0){
        setState(() => isCharging = !isCharging);
        await Future.delayed(const Duration(seconds: 5));
        setState(() => isCharging = !isCharging);

      }
    }
  }
  @override
  void initState() {
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    PackageInfo.fromPlatform().then((info) {
      setState(() => _appVersion = info.version);
    });
    super.initState();
  }

  @override
  void dispose() {
    _textController.dispose();
    _controller.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void showErrorDialog(String errorMessage) {
    showDialog(
        context: context,
        builder: (BuildContext context){
          return AlertDialog(
            title: Text(errorMessage),
            actions: [
              ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Ok", style: TextStyle(color: Colors.black),)
              ),
            ],
          );
        }
    );
  }

  Future<void> uploadPreset(Preset preset) async {
    print("Uploading Preset to device");
    setState(() => uploadingPreset = true);
    await ref.read(bluetoothNotifierProvider.notifier).uploadPresetToDevice(preset);
    await Future.delayed(const Duration(seconds: 3));
    setState(() => uploadingPreset = false);
  }

  Future<void> _applyPresetToDevice(Preset preset) async {
    ref.read(tensNotifierProvider.notifier).updateFromPreset(preset);
    ref.read(vibrationNotifierProvider.notifier).updateFromPreset(preset);
    ref.read(temperatureNotifierProvider.notifier).updateFromPreset(preset);

    String command;
    command = ref.read(bluetoothNotifierProvider.notifier).getCommand("tens");
    await ref.read(bluetoothNotifierProvider.notifier).newWriteToDevice(command);
    command = ref.read(bluetoothNotifierProvider.notifier).getCommand("temperature");
    await ref.read(bluetoothNotifierProvider.notifier).newWriteToDevice(command);
    command = ref.read(bluetoothNotifierProvider.notifier).getCommand("vibration");
    await ref.read(bluetoothNotifierProvider.notifier).newWriteToDevice(command);

    await Future.delayed(const Duration(seconds: 2));

    setState(() {
      isLoading = false;
    });
  }


  Future<void> _onPresetSelected(int index, Preset? preset) async {
    await HapticsHelper.vibrate(HapticsType.selection);
    if (preset == null) {
      print("Preset at index $index is null, using default.");
      return;
    }

    if (_selectedIndex == index) {
      print("Deselecting preset ${index + 1}");
      preset = Preset(id: index, tens: const Tens(), vibration: const Vibration(), temperature: const Temperature(), name: "");
      setState(() {
        _selectedIndex = null; // Deselect
      });

      _applyPresetToDevice(preset); // Send empty preset
      return;
    }

    print("Selected Preset: ${preset.name.isNotEmpty ? preset.name : "Preset ${index + 1}"}");

    setState(() {
      isLoading = true;
      _selectedIndex = index; // Select the new preset
    });

    _applyPresetToDevice(preset); // Load the preset normally
  }




  void _onLongPressStart(int index) {
    print("Long press start");
    setState(() {
      _loadingIndex = index;
      _progress = 0.0;
    });

    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_progress >= 1.0) {
        timer.cancel();
        _onLongPressComplete(index); // Call the completion function
      } else {
        setState(() {
          _progress += 0.05; // 3% per 100ms, reaching 1.0 in ~3 seconds
        });
      }
    });
  }

  Future<void> _showPresetDialog(BuildContext context, {String? initialText, required Function(String) onSave}) async {
    TextEditingController textController = TextEditingController(text: initialText ?? "");

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Enter Preset Name"),
          content: TextField(
            maxLength: 20,
            controller: textController,
            decoration: const InputDecoration(
              hintText: "Preset Name",
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() => _selectedIndex = null);
                Navigator.pop(context);
              }, // Cancel action
              child: const Text("Cancel", style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () {
                String enteredText = textController.text.trim();
                if (enteredText.isNotEmpty) {
                  onSave(enteredText); // Call the callback function with the text
                  Navigator.pop(context); // Close dialog
                }
              },
              child: const Text("Save", style: TextStyle(color: Colors.blue)),
            ),
          ],
        );
      },
    );
  }


  void _onLongPressCancel() {
    _resetProgress();
  }

  void _savePreset(int index, String name) {
    print("Index $index");
    print("Name $name");

    Preset preset = Preset(
      id: index + 1,
      tens: ref.read(tensNotifierProvider),
      vibration: ref.read(vibrationNotifierProvider),
      temperature: ref.read(temperatureNotifierProvider),
      name: name,
    );

    ref.read(presetListNotifierProvider.notifier).savePreset(preset);

    setState(() {
      uploadToDeviceString = "Uploading preset to device...";
    });

    uploadPreset(preset);
  }


  Future<void> _onLongPressComplete(int index) async {
    print("saved index $index");
    await HapticsHelper.vibrate(HapticsType.success);
    setState(() {
      _loadingIndex = null;
      _selectedIndex = index;
    });

    _showPresetDialog(
      context,
      initialText: "Preset ${_selectedIndex! + 1}",
      onSave: (presetName) {
        _savePreset(index, presetName);
        print("Preset saved: $presetName"); // Replace this with your logic to save the preset
      },
    );


    print("✅ Long press action completed for Preset ${index + 1}");
  }


  void _resetProgress() {
    _timer?.cancel();
    setState(() {
      _progress = 0.0;
      _loadingIndex = null;
    });
  }

  void _updateProgress () => setState(() {});

  @override
  Widget build(BuildContext context) {
    final presetNotifier = ref.watch(presetListNotifierProvider);
    final List<Preset> presets = presetNotifier.presets;
    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.offWhite,
          appBar: AppBar(
            leading: Row(
              children: [
                IconButton(
                    onPressed: () {
                      context.push('/onboarding');
                    },
                    icon: Icon(Icons.help_outline_rounded, color: Colors.grey.shade400,)
                ),
              ],
            ),
            title: const Text(
              'Pain Drain',
              style: TextStyle(
                  fontSize: 40,
                  color: Colors.white
              ),
            ),
            automaticallyImplyLeading: false,
            backgroundColor: Colors.blue.shade800,
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.info_outline, color: Colors.white),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('App Version'),
                      content: Text('Version $_appVersion'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(15.0),
              child: Stack(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20,),
                      // Generate buttons dynamically based on available presets
                      Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(3, (index) {

                          // This sees if the index is in the presets.
                          // If not we return null which disables on tap and grays button out
                          // Since id is ordered starting at 1 we have to minus 1 to match with index
                          final Preset? preset = presets.where((p) => p.id - 1 == index).isNotEmpty
                              ? presets.firstWhere((p) => p.id - 1 == index)
                              : null;

                          final String presetName = preset?.name.isNotEmpty == true ? preset!.name : "Preset ${index + 1}";
                          final bool isSelected = _selectedIndex == index;
                          final bool isLoading = _loadingIndex == index;
                          final bool isPresetAvailable = preset != null; // Ensure we check this

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0), // Adds spacing between button

                            child: SizedBox(
                              width: double.infinity,
                              child: GestureDetector(
                                onLongPressStart: (_) => _onLongPressStart(index),
                                onLongPressUp: _onLongPressCancel,
                                onLongPressCancel: _onLongPressCancel,
                                child: ElevatedButton(
                                  onPressed: isPresetAvailable ? () => _onPresetSelected(index, preset) : null,
                                  style: ElevatedButton.styleFrom(
                                    overlayColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: isSelected ? BorderSide(color: Colors.blue.shade700, width: 2) : BorderSide.none,
                                    ),
                                    backgroundColor: Colors.white,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(presetName,
                                            style: TextStyle(
                                                color: isPresetAvailable ? Colors.black : Colors.grey[800],
                                                fontSize: 16
                                            )
                                        ),
                                        const SizedBox(width: 8),
                                        if (isLoading)
                                          SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 3,
                                              value: _progress,
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade700),
                                            ),
                                          )
                                        else if (isSelected)
                                          Icon(Icons.check, color: Colors.blue.shade700),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 5,),
                      Align(
                          alignment: Alignment.centerLeft,
                          child: Row(
                              children: [
                                const Icon(Icons.info_outline_rounded, size: 20,),
                                const SizedBox(width: 5,),
                                Text("Hold down button to save and upload to device", style: TextStyle(color: Colors.grey[800]),)
                              ]
                          )
                      ),
                      const SizedBox(height: 20.0,),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text("TENS", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),),
                      ),
                      const SizedBox(height: 5.0,),
                      TensSummary(update: _updateProgress,),
                      const SizedBox(height: 10.0,),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text("TEMPERATURE", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),),
                      ),
                      const SizedBox(height: 5.0,),
                      TemperatureSummary(update: _updateProgress,),
                      const SizedBox(height: 10.0,),
                      const Align(

                        alignment: Alignment.centerLeft,
                        child: Text("VIBRATION", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),),
                      ),
                      const SizedBox(height: 5.0,),
                      VibrationSummary(update: _updateProgress,),
                      const SizedBox(height: 60.0,),
                      // if(showDebugTools)
                      //   Row(
                      //     mainAxisAlignment: MainAxisAlignment.end,
                      //     children: [
                      //       const Text("Debug Dev Info:"),
                      //       const SizedBox(width: 10.0,),
                      //       const Text("OFF"),
                      //
                      //       Switch(
                      //         value: _prefs.getDevControls(),
                      //         onChanged: (bool value) async {
                      //           setState(() {
                      //             _prefs.setDevControls(value);
                      //           });
                      //         },
                      //       ),
                      //       const Text("ON"),
                      //
                      //     ],
                      //   ),
                      // if(_prefs.getDevControls())
                      //   Column(
                      //     children: [
                      //       Text("Tens: ${tens.intensity}", style: const TextStyle(fontSize: 18),),
                      //       Text("phase: ${tens.phase}", style: const TextStyle(fontSize: 18)),
                      //       Text("temperature: ${temp.temperature}", style: const TextStyle(fontSize: 18)),
                      //       Text("Vibration: ${vibe.frequency}", style: const TextStyle(fontSize: 18)),
                      //       const SizedBox(height: 10.0,),
                      //       ElevatedButton(
                      //           onPressed: () {
                      //             setState(() {});
                      //           },
                      //           child: const Text("Refresh")
                      //       ),
                      //       const SizedBox(height: 20.0,),
                      //       ElevatedButton(
                      //           onPressed: () async {
                      //             await ref.read(bluetoothNotifierProvider.notifier).newWriteToDevice("B 2");
                      //           },
                      //           child: const Text("Fully Charged")
                      //       ),
                      //       ElevatedButton(
                      //           onPressed: () async {
                      //             await ref.read(bluetoothNotifierProvider.notifier).newWriteToDevice("B 3");
                      //           },
                      //           child: const Text("Low Battery")
                      //       ),
                      //       ElevatedButton(
                      //           onPressed: () async {
                      //             await ref.read(bluetoothNotifierProvider.notifier).newWriteToDevice("B 4");
                      //           },
                      //           child: const Text("Medium Battery")
                      //       ),
                      //       ElevatedButton(
                      //           onPressed: () async {
                      //             await ref.read(bluetoothNotifierProvider.notifier).newWriteToDevice("B 5");
                      //           },
                      //           child: const Text("Normal Operation")
                      //       ),
                      //       const SizedBox(height: 20.0,),
                      //       ElevatedButton(
                      //         onPressed: () async {
                      //           await ref.read(bluetoothNotifierProvider.notifier).disconnectDevice();
                      //         },
                      //         style: ElevatedButton.styleFrom(
                      //             backgroundColor: Colors.red
                      //         ),
                      //         child: const Text("Disconnect Device", style: TextStyle(color: Colors.white),),
                      //       ),
                      //       const SizedBox(height: 10.0,),
                      //     ],
                      //   )
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if(uploadingPreset)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.5), // Semi-transparent background overlay
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40), // Inner padding
                  decoration: BoxDecoration(
                    color: Colors.white, // Solid white background for the box
                    borderRadius: BorderRadius.circular(12), // Rounded corners
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2), // Subtle shadow for depth
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min, // Only takes the space it needs
                    crossAxisAlignment: CrossAxisAlignment.center, // Ensures text is centered
                    children: [
                      const CircularProgressIndicator(color: Colors.blue,), // Loading indicator
                      const SizedBox(height: 20),
                      Text(
                        uploadToDeviceString,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600, // Slightly bolder for Material feel
                          color: Colors.black87, // Dark text for contrast
                        ),
                        textAlign: TextAlign.center, // Centers the text inside the box
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )

      ],
    );
  }
}

class ChargingAnimation extends StatefulWidget {
  final double batteryLevel;
  const ChargingAnimation({Key? key, required this.batteryLevel}) : super(key: key);

  @override
  State<ChargingAnimation> createState() => _ChargingAnimationState();
}

class _ChargingAnimationState extends State<ChargingAnimation> {


  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.5),
      child: Center(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.center,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(150)
                ),
                child:
                CircularPercentIndicator(
                  radius: 70.0,
                  animation: true,
                  lineWidth: 10.0,
                  animationDuration: 3000,
                  animateFromLastPercent: true,
                  circularStrokeCap: CircularStrokeCap.round,
                  percent: widget.batteryLevel / 100,
                  arcType: ArcType.FULL,
                  linearGradient: LinearGradient(colors: [Colors.green, Colors.green.shade700]),
                  center: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        AnimateIcon(
                          onTap: () {},
                          iconType: IconType.continueAnimation,
                          height: 60,
                          width: 60,
                          color: Colors.white,
                          animateIcon: AnimateIcons.battery,
                        ),
                        Text("${widget.batteryLevel.toInt()}%", style: const TextStyle(color: Colors.white, fontSize: 18),),
                      ]
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}