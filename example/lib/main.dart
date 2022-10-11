import 'package:flutter/material.dart';
import 'package:heart_bpm/chart.dart';
import 'package:heart_bpm/heart_bpm.dart';

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

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<SensorValue> data = [];
  List<SensorValue> fft = [];
  List<SensorValue> bpmValues = [];
  //  Widget chart = BPMChart(data);

  bool isBPMEnabled = false;
  int bpm = 0;
  Widget? dialog;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Heart BPM Demo'),
      ),
      body: Column(
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
                        data.clear();
                        data.addAll(value);
                      });
                      // chart = BPMChart(data);
                    },
                    onFFT: (value) {
                      setState(() {
                        fft.clear();
                        fft.addAll(value);
                      });
                      // chart = BPMChart(data);
                    },
                    onBPM: (value, weight) => setState(() {
                      setState(() {
                        bpm = value;
                      });
                      if (bpmValues.length >= 100) bpmValues.removeAt(0);
                      bpmValues.add(SensorValue(
                          value: value.toDouble(), time: DateTime.now()));
                    }),
                    onNoFingerDetected: () {},
                  ),
                )
              : SizedBox(),
          isBPMEnabled && data.isNotEmpty
              ? Container(
                  decoration: BoxDecoration(border: Border.all()),
                  height: 100,
                  child: BPMChart(data),
                )
              : SizedBox(),
          isBPMEnabled && bpmValues.isNotEmpty
              ? Container(
                  decoration: BoxDecoration(border: Border.all()),
                  constraints: BoxConstraints.expand(height: 100),
                  child: BPMChart(bpmValues),
                )
              : SizedBox(),
          fft.isNotEmpty
              ? Container(
                  decoration: BoxDecoration(border: Border.all()),
                  constraints: BoxConstraints.expand(height: 100),
                  child: BPMChart(fft),
                )
              : SizedBox(),
          Text(bpm.toString()),
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
