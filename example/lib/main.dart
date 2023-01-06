import 'dart:math';

import 'package:flutter/material.dart';
import 'package:heart_bpm/chart.dart';
import 'package:heart_bpm/heart_bpm.dart';
import 'package:collection/collection.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Heart BPM Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomePage(),
    );
  }
}

class _HeartBPM {
  final double weight;
  final int value;

  _HeartBPM({
    required this.value,
    required this.weight,
  });
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<SensorValue> data = [];
  List<SensorValue> bpmValues = [];
  List<SensorValue> fftValues = [];
  //  Widget chart = BPMChart(data);

  int? currentValue;
  double? currentReliability;

  List<_HeartBPM> heartRateValues = [];

  bool isBPMEnabled = false;
  Widget? dialog;

  double? sum;
  double? weight;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Heart BPM Demo'),
      ),
      body: ListView(
        children: [
          isBPMEnabled
              ? dialog = SizedBox(
                  height: 200,
                  width: 200,
                  child: HeartBPMDialog(
                    context: context,
                    layoutType: HeartBPMDialogLayoutType.circle,
                    onRawData: (value) {
                      setState(() {
                        if (data.length >= 100) data.removeAt(0);
                        data.add(value.first);
                      });
                    },
                    onBPM: (value, kek) => setState(() {
                      if (bpmValues.length >= 100) bpmValues.removeAt(0);
                      bpmValues.add(SensorValue(
                          value: value.toDouble(), time: DateTime.now()));
                      currentValue = value;

                      heartRateValues.add(_HeartBPM(value: value, weight: kek));

                      sum = heartRateValues.reversed
                          .take(50)
                          .map((e) => e.value * e.weight)
                          .sum;
                      weight = heartRateValues.reversed
                          .take(50)
                          .map((e) => e.weight)
                          .sum;

                      currentReliability =
                          weight! / min(heartRateValues.length, 50);
                    }),
                    onFFT: (value) {
                      fftValues = value;
                    },
                  ),
                )
              : SizedBox(),
          if (bpmValues.isNotEmpty) Text('Current value: $currentValue'),
          if (bpmValues.isNotEmpty)
            Text(
              'Current value\'s reliability: ${currentReliability?.toStringAsFixed(2)}',
            ),
          if (bpmValues.isNotEmpty)
            Text(
              'FINAL VALUE: ${sum == null ? null : sum! ~/ weight!}',
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          isBPMEnabled && data.isNotEmpty
              ? Container(
                  decoration: BoxDecoration(border: Border.all()),
                  height: 180,
                  child: BPMChart(data),
                )
              : SizedBox(),
          isBPMEnabled && bpmValues.isNotEmpty
              ? Container(
                  decoration: BoxDecoration(border: Border.all()),
                  constraints: BoxConstraints.expand(height: 180),
                  child: BPMChart(bpmValues),
                )
              : SizedBox(),
          isBPMEnabled && fftValues.isNotEmpty
              ? Container(
                  decoration: BoxDecoration(border: Border.all()),
                  constraints: BoxConstraints.expand(height: 180),
                  child: BPMChart(fftValues),
                )
              : SizedBox(),
          Center(
            child: ElevatedButton.icon(
              icon: Icon(Icons.favorite_rounded),
              label: Text(isBPMEnabled ? "Stop measurement" : "Measure BPM"),
              onPressed: () => setState(() {
                if (isBPMEnabled) {
                  isBPMEnabled = false;
                  // dialog.
                } else
                  isBPMEnabled = true;
              }),
            ),
          ),
        ],
      ),
    );
  }
}
