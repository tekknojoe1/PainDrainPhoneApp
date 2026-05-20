import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pain_drain_mobile_app/providers/bluetooth_notifier.dart';
import 'package:pain_drain_mobile_app/providers/temperature_notifier.dart';
import 'package:pain_drain_mobile_app/screens/home/local_widgets/temperature_popup.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'custom_draggable_sheet.dart';

class TemperatureSummary extends ConsumerStatefulWidget {
  final Function update;
  const TemperatureSummary({Key? key, required this.update}) : super(key: key);

  @override
  ConsumerState<TemperatureSummary> createState() => _TemperatureSummaryState();
}

class _TemperatureSummaryState extends ConsumerState<TemperatureSummary> {
  //final Bluetooth _bleController = Get.find();
  String temp = "temp";
  IconData? icon;
  Color? iconColor;

  List<Color> colorGradient = [Colors.blue, Colors.blue.shade900];

  @override
  Widget build(BuildContext context) {
    final temp = ref.watch(temperatureNotifierProvider);
    final deviceStatus = ref.watch(bluetoothNotifierProvider);

    if(temp.temperature == 0){
      icon = null;
    }
    else if(temp.temperature > 0) {
      icon = const IconData(0xf672, fontFamily: CupertinoIcons.iconFont, fontPackage: CupertinoIcons.iconFontPackage);
      iconColor = Colors.red;
      colorGradient = [Colors.red, Colors.red.shade700, Colors.red.shade900];
    }
    else {
      icon = const IconData(0xf865, fontFamily: CupertinoIcons.iconFont, fontPackage: CupertinoIcons.iconFontPackage);
      iconColor = Colors.blue.shade100;
      colorGradient = [Colors.lightBlue.shade100, Colors.lightBlue.shade300, Colors.lightBlue];
    }

    return InkWell(
      hoverColor: Colors.black.withOpacity(.1),
      borderRadius: BorderRadius.circular(13.0),
      onTap: () {
        showScrollableSheet(context, const TemperaturePopup(), widget.update);
      },
      child: Card(
        elevation: 10.0,
        child: Container(
          height: 150,
          decoration: BoxDecoration(
            color: Colors.green,
            borderRadius: BorderRadius.circular(10.0),
            gradient: LinearGradient(colors: [Colors.blue, Colors.blue.shade700,Colors.blue.shade800]),

          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              CircularPercentIndicator(
                radius: 50.0,
                animation: true,
                animationDuration: 2000,
                animateFromLastPercent: true,
                circularStrokeCap: CircularStrokeCap.round,
                percent: temp.temperature.abs() / 100,
                arcType: ArcType.FULL,
                linearGradient: LinearGradient(colors: colorGradient),
                center: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        color: iconColor,
                        // CupertinoIcons.thermometer_snowflake,
                        // color: Colors.blue,
                      ),
                      const SizedBox(height: 5.0,),

                      Text(
                        "${temp.temperature.toInt()}%",
                        style: const TextStyle(fontSize: 16, color: Colors.white),
                      ),
                      // SizedBox(width: 3.0,),
                      // const Icon(
                      //   CupertinoIcons.thermometer_snowflake,
                      //   color: Colors.blue,
                      // ),
                    ]
                ),
                footer: const Text("Temperature", style: TextStyle(fontSize: 12.0, color: Colors.white),),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
