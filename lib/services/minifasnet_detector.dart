import 'dart:math';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:image/image.dart' as img;
import '../models/detection_result.dart';
import '../models/bounding_box.dart';
import 'image_processor.dart';

class MiniFASNetDetector {
  OrtSession? _session1;
  OrtSession? _session2;
  bool _isInitialized = false;

  static const int INPUT_SIZE = 80;
  static const int NUM_CLASSES = 3;
  static const int NUM_CHANNELS = 3;

  // Scale factors untuk kedua model
  static const double SCALE_1 = 2.7;
  static const double SCALE_2 = 4.0;

  bool get isInitialized => _isInitialized;

  /// Initialize ONNX Runtime dan load models
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      print('[MiniFASNet] Initializing ONNX Runtime...');

      // Initialize ONNX Runtime environment
      OrtEnv.instance.init();

      // Load model 1 (scale 2.7)
      print('[MiniFASNet] Loading model 1 (scale 2.7)...');
      final modelBytes1 = await rootBundle.load(
        'assets/models/2.7_80x80_MiniFASNetV2.onnx',
      );
      _session1 = OrtSession.fromBuffer(
        modelBytes1.buffer.asUint8List(),
        OrtSessionOptions(),
      );

      // Load model 2 (scale 4.0)
      print('[MiniFASNet] Loading model 2 (scale 4.0)...');
      final modelBytes2 = await rootBundle.load(
        'assets/models/4_0_0_80x80_MiniFASNetV1SE.onnx',
      );
      _session2 = OrtSession.fromBuffer(
        modelBytes2.buffer.asUint8List(),
        OrtSessionOptions(),
      );

      _isInitialized = true;
      print('[MiniFASNet] Initialization completed!');
    } catch (e, stackTrace) {
      print('[MiniFASNet] Initialization failed: $e');
      print(stackTrace);
      rethrow;
    }
  }

  /// Predict liveness dari image dan face bounding box
  Future<DetectionResult> predict({
    required img.Image image,
    required BoundingBox boundingBox,
  }) async {
    if (!_isInitialized) {
      throw StateError('Detector not initialized. Call initialize() first.');
    }

    final startTime = DateTime.now();

    try {
      // 1. Preprocess image untuk kedua model
      final input1 = ImageProcessor.preprocessImage(
        image: image,
        bbox: boundingBox,
        scale: SCALE_1,
      );

      final input2 = ImageProcessor.preprocessImage(
        image: image,
        bbox: boundingBox,
        scale: SCALE_2,
      );

      // 2. Create ONNX input tensors
      final inputOrt1 = OrtValueTensor.createTensorWithDataList(
        input1,
        [1, NUM_CHANNELS, INPUT_SIZE, INPUT_SIZE],
      );

      final inputOrt2 = OrtValueTensor.createTensorWithDataList(
        input2,
        [1, NUM_CHANNELS, INPUT_SIZE, INPUT_SIZE],
      );

      // 3. Run inference pada kedua model
      final runOptions = OrtRunOptions();

      // Prepare inputs as Map
      final inputs1 = {_session1!.inputNames.first: inputOrt1};
      final inputs2 = {_session2!.inputNames.first: inputOrt2};

      // Run inference
      final outputs1 = await _session1!.runAsync(runOptions, inputs1);
      final outputs2 = await _session2!.runAsync(runOptions, inputs2);

      // 4. Extract output logits
      final logits1 = (outputs1?.first?.value as List<List<double>>)[0];
      final logits2 = (outputs2?.first?.value as List<List<double>>)[0];

      // 5. Apply softmax
      final softmax1 = _softmax(logits1);
      final softmax2 = _softmax(logits2);

      // 6. Average predictions dari kedua model
      final avgScores = List<double>.generate(
        NUM_CLASSES,
        (i) => (softmax1[i] + softmax2[i]) / 2.0,
      );

      // 7. Get predicted label
      final maxScore = avgScores.reduce(max);
      final label = avgScores.indexOf(maxScore);

      // 8. Cleanup tensors
      inputOrt1.release();
      inputOrt2.release();
      outputs1?.forEach((output) => output?.release());
      outputs2?.forEach((output) => output?.release());
      runOptions.release();

      final inferenceTime = DateTime.now().difference(startTime);
      print('[MiniFASNet] Inference time: ${inferenceTime.inMilliseconds}ms');

      // 9. Create result
      return DetectionResult(
        label: label,
        labelText: DetectionResult.labelNames[label],
        isReal: label == 1,
        confidence: maxScore,
        scores: {
          'paper': avgScores[0],
          'real': avgScores[1],
          'screen': avgScores[2],
        },
        boundingBox: boundingBox,
      );
    } catch (e, stackTrace) {
      print('[MiniFASNet] Prediction error: $e');
      print(stackTrace);
      rethrow;
    }
  }

  /// Apply softmax function
  List<double> _softmax(List<double> logits) {
    final maxLogit = logits.reduce(max);
    final expValues = logits.map((x) => exp(x - maxLogit)).toList();
    final sumExp = expValues.reduce((a, b) => a + b);
    return expValues.map((x) => x / sumExp).toList();
  }

  /// Cleanup resources
  void dispose() {
    print('[MiniFASNet] Disposing resources...');
    _session1?.release();
    _session2?.release();
    _session1 = null;
    _session2 = null;
    _isInitialized = false;
    print('[MiniFASNet] Resources disposed');
  }
}
