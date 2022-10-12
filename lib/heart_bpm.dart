// library heart_bpm;

import 'dart:math';

import 'package:camera/camera.dart';
import 'package:collection/collection.dart';
import 'package:fftea/fftea.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as imglib;

class RGB {
  double red;
  double green;
  double blue;

  RGB(this.red, this.green, this.blue);

  @override
  String toString() {
    return 'RGB{red: $red, green: $green, blue: $blue}';
  }
}

/// Class to store one sample data point
class SensorValue {
  /// timestamp of datapoint
  final DateTime time;

  /// value of datapoint
  final num value;

  SensorValue({required this.time, required this.value});

  /// Returns JSON mapped data point
  Map<String, dynamic> toJSON() => {'time': time, 'value': value};

  /// Map a list of data samples to a JSON formatted array.
  ///
  /// Map a list of [data] samples to a JSON formatted array. This is
  /// particularly useful to store [data] to database.
  static List<Map<String, dynamic>> toJSONArray(List<SensorValue> data) =>
      List.generate(data.length, (index) => data[index].toJSON());
}

enum HeartBPMDialogLayoutType { defaultLayout, circle }

/// Obtains heart beats per minute using camera sensor
///
/// Using the smartphone camera, the widget estimates the skin tone variations
/// over time. These variations are due to the blood flow in the arteries
/// present below the skin of the fingertips.
// ignore: must_be_immutable
class HeartBPMDialog extends StatefulWidget {
  /// Callback used to notify the caller of updated BPM measurement
  ///
  /// Should be non-blocking as it can affect
  final void Function(int, double) onBPM;

  /// Callback used to notify the caller of updated raw data sample
  ///
  /// Should be non-blocking as it can affect
  final void Function(List<SensorValue>)? onRawData;

  final void Function(List<SensorValue>)? onFFT;

  final bool Function(double red, double green, double blue)? fingerCondition;

  /// Callback used to notify if the image is not red enough
  final void Function()? onNoFingerDetected;

  /// Callback used to notify if the image is red enough
  final void Function()? onFingerDetected;

  /// Camera sampling rate in milliseconds
  final int sampleDelay;

  /// Parent context
  final BuildContext context;

  /// Dialog layout type
  /// [HeartBPMDialogLayoutType.defaultLayout] - default layout
  /// [HeartBPMDialogLayoutType.circle] - circular layout with only camera visible
  final HeartBPMDialogLayoutType layoutType;

  /// Smoothing factor
  ///
  /// Factor used to compute exponential moving average of the realtime data
  /// using the formula:
  /// ```
  /// $y_n = alpha * x_n + (1 - alpha) * y_{n-1}$
  /// ```
  double alpha = 0.6;

  /// Additional child widget to display
  final Widget? child;

  /// Obtains heart beats per minute using camera sensor
  ///
  /// Using the smartphone camera, the widget estimates the skin tone variations
  /// over time. These variations are due to the blood flow in the arteries
  /// present below the skin of the fingertips.
  ///
  /// This is a [Dialog] widget and hence needs to be displayer using [showDialog]
  /// function. For example:
  /// ```
  /// await showDialog(
  ///   context: context,
  ///   builder: (context) => HeartBPMDialog(
  ///     onData: (value) => print(value),
  ///   ),
  /// );
  /// ```
  HeartBPMDialog({
    Key? key,
    required this.context,
    this.sampleDelay = 2000 ~/ 20,
    required this.onBPM,
    this.onFFT,
    this.onNoFingerDetected,
    this.fingerCondition,
    this.onFingerDetected,
    this.onRawData,
    this.alpha = 0.8,
    this.child,
    this.layoutType = HeartBPMDialogLayoutType.defaultLayout,
  });

  @override
  _HeartBPPView createState() => _HeartBPPView();
}

class _HeartBPPView extends State<HeartBPMDialog> {
  /// Camera controller
  CameraController? _controller;

  /// Used to set sampling rate
  bool _processing = false;

  /// Current value
  double bpmSum = 0;
  double totalWieght = 0;
  int get currentValue => totalWieght == 0 ? 0 : bpmSum ~/ totalWieght;

  int cutOffValue = 15;

  /// to ensure camara was initialized
  bool isCameraInitialized = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  @override
  void dispose() {
    _deinitController();
    super.dispose();
  }

  /// Deinitialize the camera controller
  void _deinitController() async {
    isCameraInitialized = false;
    if (_controller == null) return;
    // await _controller.stopImageStream();
    await _controller!.setFlashMode(FlashMode.off);
    await _controller!.dispose();
    // while (_processing) {}
    // _controller = null;
  }

  /// Initialize the camera controller
  ///
  /// Function to initialize the camera controller and start data collection.
  Future<void> _initController() async {
    if (_controller != null) return;
    try {
      // 1. get list of all available cameras
      List<CameraDescription> _cameras = await availableCameras();
      // 2. assign the preferred camera with low resolution and disable audio

      /// Filter front cameras
      _cameras = _cameras
          .where((element) => element.lensDirection == CameraLensDirection.back)
          .toList();

      /// Choose iPhone zoom lense as it is aligned with the flash
      final _camera = _cameras.firstWhere(
          (element) =>
              element.name ==
              'com.apple.avfoundation.avcapturedevice.built-in_video:2',
          orElse: () => _cameras.first);
      _controller = CameraController(_camera, ResolutionPreset.low,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.bgra8888);

      // 3. initialize the camera
      await _controller!.initialize();

      // 4. set torch to ON and start image stream
      Future.delayed(Duration(milliseconds: 500))
          .then((value) => _controller!.setFlashMode(FlashMode.torch));

      // 5. register image streaming callback
      _controller!.startImageStream((image) {
        if (!_processing && mounted) {
          _processing = true;
          _scanImage(image);
        }
      });

      setState(() {
        isCameraInitialized = true;
      });
    } catch (e) {
      print(e);
      throw e;
    }
  }

  static const int windowLength = 70;
  final List<SensorValue> measureWindow = List<SensorValue>.filled(
      windowLength, SensorValue(time: DateTime.now(), value: 0),
      growable: true);

  imglib.Image _convertCameraImage(
      CameraImage image, CameraLensDirection _dir) {
    imglib.Image img = imglib.Image.fromBytes(
      image.width,
      image.height,
      image.planes[0].bytes,
      format: imglib.Format.bgra,
    );
    var img1 = (_dir == CameraLensDirection.front)
        ? imglib.copyRotate(img, -90)
        : imglib.copyRotate(img, 90);
    return img1;
  }

  //Convert YUV to RGB to extract rgb values
  RGB getRGB(CameraImage cameraImage) {
    double red = 0;
    double green = 0;
    double blue = 0;

    imglib.Image image =
        _convertCameraImage(cameraImage, CameraLensDirection.back);

    int abgrToArgb(int argbColor) {
      int r = (argbColor >> 16) & 0xFF;
      int b = argbColor & 0xFF;
      return (argbColor & 0xFF00FF00) | (b << 16) | r;
    }

    for (int i = 0; i < image.data.length; i++) {
      final pixel32 = image.data[i];
      int hex = abgrToArgb(pixel32);
      Color color = Color(hex);
      red += color.red;
      blue += color.blue;
      green += color.green;
    }

    final total = image.data.length;
    final rgb = RGB(red / total, green / total, blue / total);
    return rgb;
  }

  //check if there's a finger on the camera
  bool fingerCondition(RGB rgb) {
    print(rgb.red);
    if (widget.fingerCondition != null) {
      return widget.fingerCondition!(rgb.red, rgb.green, rgb.blue);
    }
    return rgb.red > 150 && rgb.green < 100 && rgb.blue < 50;
  }

  DateTime? lastBeatTime;
  double? bpm;

  void _scanImage(CameraImage image) async {
    double _avg = getRGB(image).red;

    measureWindow.removeAt(0);
    measureWindow.add(SensorValue(time: DateTime.now(), value: _avg));

    if (!fingerCondition(getRGB(image))) {
      if (widget.onNoFingerDetected != null) {
        widget.onNoFingerDetected!();
      }
    } else {
      if (widget.onFingerDetected != null) {
        widget.onFingerDetected!();
      }
    }

    //Preprocessing data
    var data = _normalizedData(measureWindow);
    data = _smoothData(data);
    data = _detrendedData(data, 25);
    data = _detrendedData(data, 10);
    data = _detrendedData(data, 5);

    //FFT to fingure out what frequency dominates
    final fft = FFT(data.length - cutOffValue * 2);
    var freq = fft
        .realFft(data
            .sublist(cutOffValue, data.length - cutOffValue)
            .map((e) => e.value.toDouble())
            .toList())
        .discardConjugates()
        .map((e) => sqrt(e.x * e.x + e.y * e.y))
        .toList();

    int i = 0;

    //Providing with FFT data if needed
    if (widget.onFFT != null) {
      widget.onFFT!(freq
          .map((e) => SensorValue(time: data[cutOffValue + i++].time, value: e))
          .toList());
    }

    int? _maxFreqIdx = _getFreq(freq);

    //Getting the dominant frequency and updating the bpm
    if (!measureWindow.map<num>((e) => e.value).contains(0)) {
      if (_maxFreqIdx != null) {
        final tempBpm = _getBPM(
            data.sublist(cutOffValue, data.length - cutOffValue), _maxFreqIdx);

        //Weight calculates how accurate the alculations are
        //Low weight = low chnaces for calculations to be correct
        var weight = _getWeight(freq, _maxFreqIdx);
        weight *= weight;

        bpmSum += tempBpm * weight;
        totalWieght += weight;

        widget.onBPM(tempBpm, weight);
      }
    }

    widget.onRawData!(
      data.sublist(cutOffValue, windowLength - cutOffValue),
    );

    Future<void>.delayed(Duration(milliseconds: widget.sampleDelay))
        .then((onValue) {
      if (mounted)
        setState(() {
          _processing = false;
        });
    });
  }

  int _getBPM(List<SensorValue> data, int freq) {
    Duration totalTime = data.last.time.difference(data.first.time);
    double periodInMilliseonds = totalTime.inMilliseconds / freq;
    return 60 * 1000 ~/ periodInMilliseonds;
  }

  double _getWeight(List<double> freq, int maxFreqIdx) {
    bool isPeak(index) {
      return index > 0 &&
          index < freq.length - 1 &&
          freq[index] > freq[index - 1] &&
          freq[index] > freq[index + 1];
    }

    double totalPeakHeight = 0;

    for (int i = 0; i < freq.length; i++) {
      if (isPeak(i)) {
        totalPeakHeight += freq[i];
      }
    }

    return freq[maxFreqIdx] / totalPeakHeight;
  }

  int? _getFreq(List<double> modules) {
    if (modules.length < (windowLength - cutOffValue * 2) ~/ 2 + 1) return null;

    double maxx = 0;
    int? maxIndex;

    for (int i = 1; i < modules.length; i++) {
      if (modules[i] > maxx) {
        maxx = modules[i];
        maxIndex = i;
      }
    }

    return maxIndex;
  }

  var normalizeIterations = 0;

  List<SensorValue> _normalizedData(List<SensorValue> data) {
    num absoluteMax = data.map((e) => e.value.toDouble()).toList().max;
    num absoluteMin = data.map((e) => e.value.toDouble()).toList().min;

    normalizeIterations++;

    if (normalizeIterations == measureWindow.length) {
      normalizeIterations = 0;
    }

    if (normalizeIterations == 0) {
      num max = _averageMax(data.map((e) => e.value.toDouble()).toList(), 10);
      num min = _averageMin(data.map((e) => e.value.toDouble()).toList(), 10);

      return data
          .map((e) => SensorValue(
                time: e.time,
                value: ((e.value - absoluteMin) / (absoluteMax - absoluteMin))
                        .clamp(min, max) *
                    10,
              ))
          .toList();
    }

    return data
        .map((e) => SensorValue(
              time: e.time,
              value:
                  ((e.value - absoluteMin) / (absoluteMax - absoluteMin)) * 10,
            ))
        .toList();
  }

  double _averageMax(List<double> data, int spread) {
    double result = 0;
    int iterations = 0;
    for (int i = 0; i < data.length - spread; i += spread) {
      result += data.sublist(i, i + spread).max;
      iterations++;
    }
    return result / iterations;
  }

  double _averageMin(List<double> data, int spread) {
    double result = 0;
    int iterations = 0;
    for (int i = 0; i < data.length - spread; i += spread) {
      result += data.sublist(i, i + spread).min;
      iterations++;
    }
    return result / iterations;
  }

  List<SensorValue> _detrendedData(List<SensorValue> data, int spread) {
    var trend = _trend(data.map((e) => e.value).toList(), spread);

    int i = 0;
    return data
        .map((e) => SensorValue(time: e.time, value: e.value - trend[i++]))
        .toList();
  }

  List<num> _trend(List<num> data, int spread) {
    var result = <num>[];
    var sublist = <num>[];

    for (int i = 0; i < data.length; i++) {
      if (i < spread || i > data.length - spread - 1) {
        result.add(data[i]);
      } else {
        if (sublist.isEmpty) {
          sublist = data.sublist(i - spread, i + spread);
        } else {
          sublist.removeAt(0);
          sublist.add(data[i + spread]);
        }
        result.add(sublist.average);
      }
    }

    for (int i = 0; i < spread; i++) {
      result[i] = result[spread];
    }

    for (int i = result.length - spread; i < result.length; i++) {
      result[i] = result[result.length - spread - 1];
    }

    return result;
  }

  List<SensorValue> _smoothData(List<SensorValue> data) {
    var values = data.map((e) => e.value).toList();

    var ema = [];
    ema.add(values[0]);

    final ratio = (20) / (values.length + 1);

    for (int i = 1; i < values.length; i++) {
      ema.add(
        values[i] * ratio + ema[i - 1] * (1 - ratio),
      );
    }

    int i = 0;
    return data.map((e) => SensorValue(time: e.time, value: ema[i++])).toList();
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.layoutType) {
      case HeartBPMDialogLayoutType.defaultLayout:
        return Container(
          child: isCameraInitialized
              ? Column(
                  children: [
                    Container(
                      constraints:
                          BoxConstraints.tightFor(width: 100, height: 130),
                      child: _controller!.buildPreview(),
                    ),
                    Text(currentValue.toStringAsFixed(0)),
                    widget.child == null ? SizedBox() : widget.child!,
                  ],
                )
              : Center(child: CircularProgressIndicator()),
        );

      case HeartBPMDialogLayoutType.circle:
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: isCameraInitialized
              ? LayoutBuilder(builder: (context, constraints) {
                  return Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                    ),
                    child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(constraints.maxWidth / 2),
                        child: _controller!.buildPreview()),
                  );
                })
              : Center(child: CircularProgressIndicator.adaptive()),
        );
    }
  }
}
