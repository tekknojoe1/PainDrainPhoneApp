import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:location/location.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pain_drain_mobile_app/providers/bluetooth_notifier.dart';
import 'package:pain_drain_mobile_app/providers/temperature_notifier.dart';
import 'package:pain_drain_mobile_app/providers/tens_notifier.dart';
import 'package:pain_drain_mobile_app/providers/vibration_notifier.dart';
import 'package:pain_drain_mobile_app/utils/app_colors.dart';
import '../../utils/globals.dart';
import '../../utils/haptic_feedback.dart';
import '../../widgets/bluetooth_icon_animation.dart';
import '../../widgets/check_mark_animation.dart';
import '../../widgets/x_mark_animation.dart';

class ConnectDevice extends ConsumerStatefulWidget {
  final bool? wasDisconnected;
  const ConnectDevice({Key? key, this.wasDisconnected}) : super(key: key);

  @override
  ConsumerState<ConnectDevice> createState() => _ConnectDeviceState();
}

class _ConnectDeviceState extends ConsumerState<ConnectDevice> with SingleTickerProviderStateMixin {
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;

  late StreamSubscription<BluetoothAdapterState> _adapterStateStateSubscription;
  late AnimationController _animationController;
  late Animation<double> _animation;
  //final Bluetooth _bleController = Get.find<Bluetooth>();
  //final Stimulus _stimulusController = Get.find();

  bool showCheckMark = false;
  bool showXMark =  false;
  bool isPulsing = false;
  String _appVersion = '';



  @override
  @override
  void initState() {
    super.initState();
    // Check if `wasDisconnected` is true and show the SnackBar after the first frame is built
    if (widget.wasDisconnected == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showSnackBar(context);
      });
    }

    _adapterStateStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      _adapterState = state;
    });
    PackageInfo.fromPlatform().then((info) {
      setState(() => _appVersion = info.version);
    });
    _animationController = AnimationController(vsync: this, duration: const Duration(seconds: 1));
    _animation = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
            parent: _animationController, curve: Curves.easeInOutCirc
        )
    );
  }

  @override
  void dispose() {
    _adapterStateStateSubscription.cancel();
    super.dispose();
  }

  void _showSnackBar(BuildContext context) {
    const snackBar = SnackBar(
      backgroundColor: Colors.black45,
      content: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Device was disconnected!', style: TextStyle(fontSize: 18),),
            Icon(Icons.warning_amber, color: Colors.yellow,)
          ]
      ),
      duration: Duration(seconds: 4), // Optional: duration for how long it shows
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  Future<void> _checkPermissions() async {

    // Checking to make sure location services is on
    Location location = Location();

    bool serviceEnabled;
    PermissionStatus permissionGranted;

    serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        return;
      }
    }

    permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        return;
      }
    }
  }


  Future<void> scanAndConnect() async {

    await _checkPermissions();

    if(isDebug){
      //Get.off(() => const HomeScreen());
      context.go('/home');
      return;
    }
    String errorMessage;
    String solution;
    setState(() {
      isPulsing = true;
    });

    if(_adapterState == BluetoothAdapterState.on){
      print("Bluetooth is on");
      await ref.read(bluetoothNotifierProvider.notifier).scanForDevices();

      List<ScanResult> results = ref.read(bluetoothNotifierProvider).scanResults;

      if(results.isNotEmpty){
        BluetoothDevice device = results.first.device;
        print(device);
        bool success = await ref.read(bluetoothNotifierProvider.notifier).connectDevice(device);
        if(success) {
          setState(() {
            isPulsing = false;
            showCheckMark = true;
            _animationController.forward();
          });
          await HapticsHelper.vibrate(HapticsType.success);
          await Future.delayed(const Duration(seconds: 2));
          ref.read(tensNotifierProvider.notifier).disableTens();
          ref.read(vibrationNotifierProvider.notifier).disableVibe();
          ref.read(temperatureNotifierProvider.notifier).disableTemp();

         // _stimulusController.disableAllStimuli(); // This makes sure we are starting with nothing on
          //Get.off(() => const HomeScreen());
          context.go('/home');
          print("success");
        }
        else {

          errorMessage = "Connection Failed";
          solution = "Please try again";
          setState(() {
            isPulsing = false;
            showXMark = true;
            _animationController.forward();
          });
          await HapticsHelper.vibrate(HapticsType.error);
          await Future.delayed(const Duration(seconds: 2));

          setState(() {
            showXMark = false;
            _animationController.reset();
          });
          print("Unsuccessful Connection: Could not connect to PainDrain device");
          _showDialog(errorMessage, solution);
        }
      }
      else {
        errorMessage = "Could not find device";
        solution = "Make sure device is on and awake and then try again";
        setState(() {
          isPulsing = false;
          showXMark = true;
          _animationController.forward();
        });
        await HapticsHelper.vibrate(HapticsType.error);
        await Future.delayed(const Duration(seconds: 1));
        setState(() {
          showXMark = false;
          _animationController.reset();

        });
        print("Unsuccessful Scan: No results for PainDrain found");
        _showDialog(errorMessage, solution);
      }
      print("List ${ref.read(bluetoothNotifierProvider).scanResults}");
    } else{
      errorMessage = "Bluetooth not enabled";
      solution = "Please make sure to enable bluetooth on your device";
      _showDialog(errorMessage, solution);

      setState(() {
        isPulsing = false;
      });
      if (Platform.isAndroid) {
        await FlutterBluePlus.turnOn();
      }
    }
  }

  void _showDialog(String errorMessage, String solution){
    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(errorMessage),
            content: Text(solution),
            actions: [
              MaterialButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text("Ok"),
              ),
            ],
          );
        });
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: Stack(
        children: [
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.info_outline, color: Colors.grey),
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
          ),
          Positioned(
            top: MediaQuery.of(context).size.height / 2 - 200, // Adjust the value as needed
            left: (MediaQuery.of(context).size.width - 180) / 2, // Adjust the value as needed
            child: SizedBox(
              width: 180,
              height: 180,
              child: Center(
                child: showCheckMark
                    ? SuccessfulConnection(animation: _animation)
                    : (showXMark
                    ? UnsuccessfulConnection(animation: _animation)
                    : PulseIcon(isPulsing: isPulsing)),
              ),
            ),
          ),
          //ElevatedButton(onPressed: _showDialog, child: Text("Test")),

          Align(
            alignment: Alignment.bottomCenter,
              child: CustomPaint(
                size: Size(MediaQuery.of(context).size.width, 270),
                painter: CurvePainter(color: Colors.lightBlue),
              )
            // child:
            //
            // ClipPath(
            //   clipper: ConnectBottomScreenClipper(),
            //   child: Container(
            //     color: Colors.lightBlue, //AppColors.amber.withOpacity(.7),
            //     height: 525,
            //     width: MediaQuery.of(context).size.width,
            //   ),
            // ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: CustomPaint(
              size: Size(MediaQuery.of(context).size.width, 250),
              painter: CurvePainter(color: Colors.blue.shade700),
            )
            // ClipPath(
            //   clipper: ConnectBottomScreenClipper(),
            //   child: Container(
            //     color: Colors.blue.shade700,
            //     height: 500,
            //     width: MediaQuery.of(context).size.width,
            //   ),
            // ),
          ),
          Positioned(
            bottom: 30,
            // left: 0,
            child: SizedBox(
              width: MediaQuery.of(context).size.width,
              child: Padding(
                padding: const EdgeInsets.all(5.0),
                child: Column(
                  children: [
                    const Text("Press 'CONNECT' to connect", style: TextStyle(color: AppColors.offWhite, fontSize: 20),),
                    const SizedBox(height: 3,),
                    const Text("to Pain Drain device", style: TextStyle(color: AppColors.offWhite, fontSize: 20),),
                    const SizedBox(height: 30,),
                    SizedBox(
                      width: 200,
                      height: 60,
                      child: ElevatedButton(
                        onPressed: () async {
                          print("Connect pressed");
                          if(!isPulsing){

                            await scanAndConnect();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.lightBlue,

                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20.0),
                          ),
                        ),
                        child: Text(
                          isPulsing ? 'CONNECTING' : 'CONNECT',
                          style: const TextStyle(fontSize: 18, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CurvePainter extends CustomPainter {
  final Color color;

  CurvePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    double leftXPoint = size.width * .2;
    double leftYPoint = size.height * .3;
    double rightXPoint = size.width - (size.width * .2);
    double rightYPoint = size.height * -.3;
    double centerXPoint = size.width / 2;
    var paint = Paint()..color = color;

    var path = Path()
      ..moveTo(0, 0) // Top left point of the container
      ..quadraticBezierTo(leftXPoint, leftYPoint, centerXPoint, 0)
      ..quadraticBezierTo(rightXPoint, rightYPoint, size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}