// library heart_bpm;

import 'dart:math';
import 'package:image/image.dart' as imglib;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class RGB {
  double red;
  double green;
  double blue;

  RGB(this.red, this.green, this.blue);
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
  final void Function(int) onBPM;

  /// Callback used to notify the caller of updated raw data sample
  ///
  /// Should be non-blocking as it can affect
  final void Function(SensorValue)? onRawData;

  /// Callback used to notify if the image is not red enough
  final void Function()? onNoFingerDetected;

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
    this.sampleDelay = 2000 ~/ 30,
    required this.onBPM,
    this.onNoFingerDetected,
    this.onRawData,
    this.alpha = 0.8,
    this.child,
    this.layoutType = HeartBPMDialogLayoutType.defaultLayout,
  });

  /// Set the smoothing factor for exponential averaging
  ///
  /// the scaling factor [alpha] is used to compute exponential moving average of the
  /// realtime data using the formula:
  /// ```
  /// $y_n = alpha * x_n + (1 - alpha) * y_{n-1}$
  /// ```
  void setAlpha(double a) {
    if (a <= 0)
      throw Exception(
          "$HeartBPMDialog: smoothing factor cannot be 0 or negative");
    if (a > 1)
      throw Exception(
          "$HeartBPMDialog: smoothing factor cannot be greater than 1");
    alpha = a;
  }

  @override
  _HeartBPPView createState() => _HeartBPPView();
}

class _HeartBPPView extends State<HeartBPMDialog> {
  /// Camera controller
  CameraController? _controller;

  /// Used to set sampling rate
  bool _processing = false;

  /// Current value
  int currentValue = 0;

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
          enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);

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

  static const int windowLength = 50;
  final List<SensorValue> measureWindow = List<SensorValue>.filled(
      windowLength, SensorValue(time: DateTime.now(), value: 0),
      growable: true);

  double _getRed(CameraImage cameraImage) {
    final imageWidth = cameraImage.width;
    final imageHeight = cameraImage.height;

    final yBuffer = cameraImage.planes[0].bytes;
    final uBuffer = cameraImage.planes[1].bytes;
    final vBuffer = cameraImage.planes[2].bytes;

    final int yRowStride = cameraImage.planes[0].bytesPerRow;
    final int yPixelStride = cameraImage.planes[0].bytesPerPixel!;

    final int uvRowStride = cameraImage.planes[1].bytesPerRow;
    final int uvPixelStride = cameraImage.planes[1].bytesPerPixel!;

    double red = 0;

    for (int h = 0; h < imageHeight; h++) {
      int uvh = (h / 2).floor();

      for (int w = 0; w < imageWidth; w++) {
        int uvw = (w / 2).floor();

        final yIndex = (h * yRowStride) + (w * yPixelStride);
        final int y = yBuffer[yIndex];

        final int uvIndex = (uvh * uvRowStride) + (uvw * uvPixelStride);
        final int v = vBuffer[uvIndex];

        int r = (y + v * 1436 / 1024 - 179).round();
        r = r.clamp(0, 255);
        red += r;
      }
    }

    return red / (imageHeight * imageWidth);
  }

  RGB getRGB(CameraImage cameraImage) {
    final imageWidth = cameraImage.width;
    final imageHeight = cameraImage.height;

    final yBuffer = cameraImage.planes[0].bytes;
    final uBuffer = cameraImage.planes[1].bytes;
    final vBuffer = cameraImage.planes[2].bytes;

    final int yRowStride = cameraImage.planes[0].bytesPerRow;
    final int yPixelStride = cameraImage.planes[0].bytesPerPixel!;

    final int uvRowStride = cameraImage.planes[1].bytesPerRow;
    final int uvPixelStride = cameraImage.planes[1].bytesPerPixel!;

    double red = 0;
    double green = 0;
    double blue = 0;

    for (int h = 0; h < imageHeight; h++) {
      int uvh = (h / 2).floor();

      for (int w = 0; w < imageWidth; w++) {
        int uvw = (w / 2).floor();

        final yIndex = (h * yRowStride) + (w * yPixelStride);

        final int y = yBuffer[yIndex];
        final int uvIndex = (uvh * uvRowStride) + (uvw * uvPixelStride);

        final int u = uBuffer[uvIndex];
        final int v = vBuffer[uvIndex];

        int r = (y + v * 1436 / 1024 - 179).round();
        int g = (y - u * 46549 / 131072 + 44 - v * 93604 / 131072 + 91).round();
        int b = (y + u * 1814 / 1024 - 227).round();

        red += r.clamp(0, 255);
        green += g.clamp(0, 255);
        blue += b.clamp(0, 255);
      }
    }

    final total = imageWidth * imageHeight;
    return RGB(red / total, green / total, blue / total);
  }

  bool fingerCondition(RGB rgb) {
    return rgb.red > 150 && rgb.green < 100 && rgb.blue < 50;
  }

  void _scanImage(CameraImage image) async {
    // make system busy
    // setState(() {
    //   _processing = true;
    // });

    // get the average value of the image
    double _avg =
        image.planes.first.bytes.reduce((value, element) => value + element) /
            image.planes.first.bytes.length;

    measureWindow.removeAt(0);
    measureWindow.add(SensorValue(time: DateTime.now(), value: _avg));

    if (!fingerCondition(getRGB(image))) {
      if (widget.onNoFingerDetected != null) {
        widget.onNoFingerDetected!();
      }
    }

    _smoothBPM(_avg).then((value) {
      widget.onRawData!(
        // call the provided function with the new data sample
        SensorValue(
          time: DateTime.now(),
          value: _avg,
        ),
      );

      Future<void>.delayed(Duration(milliseconds: widget.sampleDelay))
          .then((onValue) {
        if (mounted)
          setState(() {
            _processing = false;
          });
      });
    });
  }

  /// Smooth the raw measurements using Exponential averaging
  /// the scaling factor [alpha] is used to compute exponential moving average of the
  /// realtime data using the formula:
  /// ```
  /// $y_n = alpha * x_n + (1 - alpha) * y_{n-1}$
  /// ```
  Future<int> _smoothBPM(double newValue) async {
    double maxVal = 0, _avg = 0;

    measureWindow.forEach((element) {
      _avg += element.value / measureWindow.length;
      if (element.value > maxVal) maxVal = element.value as double;
    });

    double _threshold = (maxVal + _avg) / 2;
    int _counter = 0, previousTimestamp = 0;
    double _tempBPM = 0;
    for (int i = 1; i < measureWindow.length; i++) {
      // find rising edge
      if (measureWindow[i - 1].value < _threshold &&
          measureWindow[i].value > _threshold) {
        if (previousTimestamp != 0) {
          _counter++;
          _tempBPM += 60000 /
              (measureWindow[i].time.millisecondsSinceEpoch -
                  previousTimestamp); // convert to per minute
        }
        previousTimestamp = measureWindow[i].time.millisecondsSinceEpoch;
      }
    }

    if (_counter > 0) {
      _tempBPM /= _counter;
      _tempBPM = (1 - widget.alpha) * currentValue + widget.alpha * _tempBPM;
      setState(() {
        currentValue = _tempBPM.toInt();
        // _bpm = _tempBPM;
      });
      widget.onBPM(currentValue);
    }

    // double newOut = widget.alpha * newValue + (1 - widget.alpha) * _pastBPM;
    // _pastBPM = newOut;
    return currentValue;
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
