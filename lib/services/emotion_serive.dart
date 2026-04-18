import 'package:emotion_detection/utils/constants/app_assets.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart';

class EmotionService {
  late Interpreter _interpreter;
  late List<String> labels;

  Future<void> init() async {
    _interpreter = await Interpreter.fromAsset(AppAssets.emotionModel);
    labels = await _loadLabels();
  }

  Future<List<String>> _loadLabels() async {
    final data = await rootBundle.loadString(AppAssets.labels);
    return data.trim().split('\n');
  }

  List<double> predict(List input) {
    var output = List<double>.filled(
      1 * labels.length,
      0.0,
    ).reshape([1, labels.length]);
    _interpreter.run(input, output);
    return (output[0] as List).cast<double>();
  }
}
