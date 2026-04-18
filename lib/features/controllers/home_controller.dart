import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:emotion_detection/services/emotion_serive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

class HomeController extends GetxController {
  late CameraController cameraController;
  final EmotionService _service = EmotionService();
  late FaceDetector faceDetector;

  var isCameraInitialized = false.obs;
  var currentEmotion = "Detecting...".obs;

  Timer? _timer;
  int sensorOrientation = 0;

  @override
  void onInit() {
    super.onInit();
    faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: false,
        enableLandmarks: false,
      ),
    );
    initAll();
  }

  Future<void> initAll() async {
    await _service.init();
    await initCamera();
    startDetection();
  }

  Future<void> initCamera() async {
    final cameras = await availableCameras();
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
    );

    sensorOrientation = front.sensorOrientation;

    cameraController = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await cameraController.initialize();
    isCameraInitialized.value = true;
  }

  bool isProcessing = false;

  void startDetection() {
    cameraController.startImageStream((CameraImage image) async {
      if (isProcessing) return;

      isProcessing = true;

      try {
        final inputImage = _inputImageFromCameraImage(image);
        if (inputImage == null) {
          currentEmotion.value = "Fmt unsupported";
          isProcessing = false;
          return;
        }

        final faces = await faceDetector.processImage(inputImage);

        if (faces.isEmpty) {
          currentEmotion.value = "No face";
        } else {
          // get the largest face by bounding box area
          faces.sort(
            (a, b) => (b.boundingBox.width * b.boundingBox.height).compareTo(
              a.boundingBox.width * a.boundingBox.height,
            ),
          );
          final face = faces.first;

          final input = processCameraImage(image, face.boundingBox);
          if (input.isNotEmpty) {
            final output = _service.predict(input);
            currentEmotion.value = getEmotion(output);
          } else {
            currentEmotion.value = "Crop failed";
          }
        }
      } catch (e) {
        print("Error: $e");
        currentEmotion.value = "Err: ${e.toString().split('\n').first}";
      }

      await Future.delayed(Duration(milliseconds: 200));

      isProcessing = false;
    });
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final imageRotation =
        InputImageRotationValue.fromRawValue(sensorOrientation) ??
        InputImageRotation.rotation90deg;

    if (Platform.isAndroid && image.format.group == ImageFormatGroup.yuv420) {
      final nv21Bytes = _yuv420ToNv21(image);
      return InputImage.fromBytes(
        bytes: nv21Bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: imageRotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    }

    InputImageFormat? format = InputImageFormatValue.fromRawValue(
      image.format.raw,
    );
    if (format == null) {
      if (image.format.group == ImageFormatGroup.bgra8888) {
        format = InputImageFormat.bgra8888;
      } else if (image.format.group == ImageFormatGroup.nv21) {
        format = InputImageFormat.nv21;
      }
    }

    if (format == null) return null;

    final bytes = WriteBuffer();
    for (final plane in image.planes) {
      bytes.putUint8List(plane.bytes);
    }
    final allBytes = bytes.done().buffer.asUint8List();

    return InputImage.fromBytes(
      bytes: allBytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: imageRotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  Uint8List _yuv420ToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final yBuffer = yPlane.bytes;
    final uBuffer = uPlane.bytes;
    final vBuffer = vPlane.bytes;

    final numPixels = width * height;
    final nv21 = Uint8List(numPixels + (numPixels ~/ 2));

    int idY = 0;
    int idUV = numPixels;

    final uvWidth = width ~/ 2;
    final uvHeight = height ~/ 2;

    for (int y = 0; y < height; y++) {
      int yOffset = y * yPlane.bytesPerRow;
      for (int x = 0; x < width; x++) {
        nv21[idY++] = yBuffer[yOffset + x];
      }
    }

    for (int y = 0; y < uvHeight; y++) {
      int uOffset = y * uPlane.bytesPerRow;
      int vOffset = y * vPlane.bytesPerRow;

      for (int x = 0; x < uvWidth; x++) {
        nv21[idUV++] = vBuffer[vOffset + (x * vPlane.bytesPerPixel!)];
        nv21[idUV++] = uBuffer[uOffset + (x * uPlane.bytesPerPixel!)];
      }
    }

    return nv21;
  }

  String getEmotion(List<double> output) {
    int maxIndex = 0;
    double maxValue = output[0];

    for (int i = 0; i < output.length; i++) {
      if (output[i] > maxValue) {
        maxValue = output[i];
        maxIndex = i;
      }
    }

    return _service.labels[maxIndex];
  }

  List processCameraImage(CameraImage image, Rect boundingBox) {
    img.Image? decodedImage;
    if (image.format.group == ImageFormatGroup.yuv420) {
      decodedImage = _convertYUV420ToImage(image);
    } else if (image.format.group == ImageFormatGroup.bgra8888) {
      decodedImage = _convertBGRA8888ToImage(image);
    }

    if (decodedImage == null) return [];

    final rotatedImage = img.copyRotate(decodedImage, angle: sensorOrientation);

    final cropX = boundingBox.left.toInt().clamp(0, rotatedImage.width);
    final cropY = boundingBox.top.toInt().clamp(0, rotatedImage.height);
    final cropW = boundingBox.width.toInt().clamp(
      0,
      rotatedImage.width - cropX,
    );
    final cropH = boundingBox.height.toInt().clamp(
      0,
      rotatedImage.height - cropY,
    );

    if (cropW <= 0 || cropH <= 0) return [];

    final croppedImage = img.copyCrop(
      rotatedImage,
      x: cropX,
      y: cropY,
      width: cropW,
      height: cropH,
    );

    final resizedImage = img.copyResize(croppedImage, width: 48, height: 48);
    final grayscaleImage = img.grayscale(resizedImage);

    // Assumes typically a [1, 48, 48, 1] shape for facial emotion tflite models
    List<List<List<List<double>>>> input = List.generate(
      1,
      (i) => List.generate(
        48,
        (y) => List.generate(48, (x) {
          final pixel = grayscaleImage.getPixel(x, y);
          final normalized = pixel.r / 255.0;
          return [normalized.toDouble()];
        }),
      ),
    );

    return input;
  }

  img.Image _convertBGRA8888ToImage(CameraImage cameraImage) {
    return img.Image.fromBytes(
      width: cameraImage.width,
      height: cameraImage.height,
      bytes: cameraImage.planes[0].bytes.buffer,
      order: img.ChannelOrder.bgra,
    );
  }

  img.Image _convertYUV420ToImage(CameraImage cameraImage) {
    final width = cameraImage.width;
    final height = cameraImage.height;

    final uvRowStride = cameraImage.planes[1].bytesPerRow;
    final uvPixelStride = cameraImage.planes[1].bytesPerPixel ?? 1;

    final imageBytes = img.Image(width: width, height: height);

    for (var y = 0; y < height; y++) {
      var pY = y * cameraImage.planes[0].bytesPerRow;
      var pUV = (y >> 1) * uvRowStride;

      for (var x = 0; x < width; x++) {
        final yp = cameraImage.planes[0].bytes[pY];
        final up = cameraImage.planes[1].bytes[pUV];
        final vp = cameraImage.planes[2].bytes[pUV];

        int r = (yp + vp * 1436 / 1024 - 179).round().clamp(0, 255);
        int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91)
            .round()
            .clamp(0, 255);
        int b = (yp + up * 1814 / 1024 - 227).round().clamp(0, 255);

        imageBytes.setPixelRgb(x, y, r, g, b);

        pY++;
        if ((x % 2) == 1) pUV += uvPixelStride;
      }
    }
    return imageBytes;
  }

  @override
  void onClose() {
    faceDetector.close();
    cameraController.dispose();
    _timer?.cancel();
    super.onClose();
  }
}
