import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:camerawesome/pigeon.dart';
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_liveness_detection/models/bounding_box.dart';
import 'package:flutter_liveness_detection/models/detection_result.dart';
import 'package:flutter_liveness_detection/models/liveness_detection_step.dart';
import 'package:flutter_liveness_detection/models/liveness_step_item.dart';
import 'package:flutter_liveness_detection/models/liveness_threshold.dart';
import 'package:flutter_liveness_detection/services/image_processor.dart';
import 'package:flutter_liveness_detection/services/minifasnet_detector.dart';
import 'package:flutter_liveness_detection/utils/mlkit_utils.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:rxdart/rxdart.dart';
import 'package:collection/collection.dart';
import 'package:loading_progress/loading_progress.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:flutter_stepindicator/flutter_stepindicator.dart';
import 'package:image/image.dart' as img;

class LivenessDetection extends StatefulWidget {

  final List<LivenessDetectionStepItem> steps;
  final List<LivenessThreshold>? thresholds;
  final bool enableScreenReplayDetection;

  const LivenessDetection({super.key, required this.steps, this.thresholds, this.enableScreenReplayDetection = false});

  @override
  State<LivenessDetection> createState() => _LivenessDetectionState();
}

class _LivenessDetectionState extends State<LivenessDetection> {

  late final List<LivenessDetectionStepItem> steps;
  final _faceDetectionController = BehaviorSubject<FaceDetectionModel>();
  AnalysisPreview? _preview;
  PhotoCameraState? _photoCameraState;

  late MiniFASNetDetector _miniFasDetector;
  bool _isDetectorInitialized = false;
  bool _isProcessing = false;
  DetectionResult? _lastResult;
  String _statusMessage = 'Initializing...';
  DateTime? _lastDetectionTime;

  // Optimization: Detection cooldown (ms)
  static const int DETECTION_COOLDOWN = 500; // 2 seconds between detections

  bool _isLoading = false;
  bool _isProcessingStep = false;
  bool _isLoadingStep = false;
  bool _isFinish = false;
  bool _isTakingPicture = false;

  String _finishProcessMessage = "Pengambilan Foto";

  List<LivenessThreshold> _thresholds = [];
  List list = [];

  Timer? _timerToDetectFace;

  int _currentStep = 0;

  final options = FaceDetectorOptions(
    enableContours: true,
    enableClassification: true,
  );
  late final faceDetector = FaceDetector(options: options);

  @override
  void initState() {
    _preInitCallBack();
    super.initState();
    _initializeDetector();
  }

  @override
  void deactivate() {
    faceDetector.close();
    super.deactivate();
  }

  @override
  void dispose() {
    _timerToDetectFace?.cancel();
    _timerToDetectFace = null;
    _faceDetectionController.close();
    if(_photoCameraState != null) _photoCameraState!.dispose();
    super.dispose();
  }

  Future<void> _initializeDetector() async {
    if(!widget.enableScreenReplayDetection) return;
    try {
      _isLoading = true;
      setState(() => _statusMessage = 'Loading AI models...');
      _miniFasDetector = MiniFASNetDetector();
      await _miniFasDetector.initialize();
      _isLoading = false;
      setState(() {
        _isDetectorInitialized = true;
        _statusMessage = 'Position your face in the frame';
      });
      debugPrint('[CameraAwesome] MiniFASNet detector initialized');
    } catch (e) {
      _isLoading = false;
      debugPrint('[CameraAwesome] Initialization error: $e');
      setState(() => _statusMessage = 'Error: ${e.toString()}');
    }
  }

  void _preInitCallBack() {
    steps = widget.steps;
    if(widget.thresholds != null) _thresholds = widget.thresholds!;
    list.addAll(steps);
  }

  void _resetSteps() {
    setState(() {
      _currentStep = 0;
      _isFinish = false;
      _isProcessingStep = false;
      _isLoadingStep = false;
      _isProcessing = false;
      _isTakingPicture = false;
      _lastResult = null;
      _statusMessage = 'Position your face in the frame';
    });
  }

  Future<void> _showSpoofingDetectedDialog({String? errorMsg}) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon with animation
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_rounded,
                    size: 50,
                    color: Color(0xFFD32F2F),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Text(
                  errorMsg != null ? "Info" : 'Spoofing Terdeteksi!',
                  style: GoogleFonts.workSans(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFD32F2F),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Message
                Text(
                    errorMsg ?? 'Sistem mendeteksi bahwa wajah Anda tidak asli. Mohon gunakan wajah asli untuk verifikasi.',
                  style: GoogleFonts.workSans(
                    fontSize: 15,
                    color: const Color(0xFF666666),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Buttons
                Row(
                  children: [
                    // Cancel Button
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).pop(null);
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: const BorderSide(
                            color: Color(0xFFD32F2F),
                            width: 2,
                          ),
                        ),
                        child: Text(
                          'Keluar',
                          style: GoogleFonts.workSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFD32F2F),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    /*// Retry Button
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _resetSteps();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color.fromARGB(255, 0, 112, 224),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Coba Lagi',
                          style: GoogleFonts.workSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),*/
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _processImage(List<Face> faces) async{
    if(_isFinish){
      await Future.delayed(const Duration(seconds: 2),);
      _takePicture(faces);
      return;
    }

    // Continue with liveness detection
    if(faces.isEmpty) return;
    _detect(
      face: faces.first,
      step: steps[_currentStep < steps.length - 1 ? _currentStep : steps.length - 1].step,
    );
  }

  Future<String?> _performAntiSpoofingDetectionFile(File imageFile) async {
    try {
      late InputImage inputImage;
      Directory? tempDir;

      if (Platform.isAndroid) {
        // Android: Use original file directly
        inputImage = InputImage.fromFile(imageFile);
      } else {
        // iOS: Fix EXIF orientation issue
        final bytes = await imageFile.readAsBytes();
        final decoded = img.decodeImage(bytes);

        if (decoded == null) {
          return "Gambar invalid";
        }

        final decodedImage = img.bakeOrientation(decoded);
        tempDir = await Directory.systemTemp.createTemp('face_detection_');
        final tempFile = File('${tempDir.path}/corrected_image.jpg');
        await tempFile.writeAsBytes(img.encodeJpg(decodedImage));
        inputImage = InputImage.fromFilePath(tempFile.path);
      }

      final faces = await faceDetector.processImage(inputImage);

      // Clean up temp file (iOS only)
      if (tempDir != null) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }

      if (faces.isEmpty) {
        return "Wajah tidak ditemukan";
      }

      if (faces.length > 1) {
        return 'Terlalu banyak wajah terdeteksi (maksimal 1 wajah)';
      }

      // Decode image for anti-spoofing
      final bytes = await imageFile.readAsBytes();
      final decoded = img.decodeImage(bytes);

      if (decoded == null) {
        return "Gambar invalid";
      }

      final decodedImage = img.bakeOrientation(decoded);

      final largestFace = faces.reduce(
        (a, b) => (a.boundingBox.width * a.boundingBox.height) >
                (b.boundingBox.width * b.boundingBox.height)
            ? a
            : b,
      );

      final bbox = BoundingBox.fromRect(largestFace.boundingBox);

      final result = await _miniFasDetector.predict(
        image: decodedImage,
        boundingBox: bbox,
      );

      if (!result.isReal) {
        return 'FAKE DETECTED (${result.labelText})';
      }

      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<bool> _performAntiSpoofingDetection(List<Face> faces) async {
    if (!_isDetectorInitialized || _isProcessing) {
      return true;
    }

    if (faces.isEmpty) {
      if (mounted) {
        setState(() {
          _lastResult = null;
          _statusMessage = 'No face detected - Move closer';
        });
      }
      return true;
    }

    _isProcessing = true;

    try {
      // Get the largest face
      final largestFace = faces.reduce(
        (a, b) => (a.boundingBox.width * a.boundingBox.height) >
                (b.boundingBox.width * b.boundingBox.height)
            ? a
            : b,
      );

      final faceModel = _faceDetectionController.valueOrNull;
      if (faceModel == null || faceModel.img == null) {
        _isProcessing = false;
        return true; // Fallback to allow picture
      }

      // Convert AnalysisImage to img.Image for MiniFASNet
      final image = ImageProcessor.convertFromAnalysisImage(faceModel.img!);
      if (image == null) {
        debugPrint('[CameraAwesome] Failed to convert image');
        _isProcessing = false;
        return true; // Fallback to allow picture
      }

      // Convert face bounding box to our BoundingBox format
      final bbox = BoundingBox.fromRect(largestFace.boundingBox);

      debugPrint('[CameraAwesome] Running anti-spoofing detection...');

      // Run anti-spoofing detection
      final result = await _miniFasDetector.predict(
        image: image,
        boundingBox: bbox,
      );

      debugPrint('[CameraAwesome] Result: ${result.statusText} (${result.confidence.toStringAsFixed(3)})');

      // Update UI with anti-spoofing result
      if (mounted) {
        setState(() {
          _lastResult = result;
          _statusMessage = result.isReal
              ? 'REAL FACE DETECTED ✓'
              : 'FAKE DETECTED (${result.labelText})';
        });
      }

      // Wait a moment to show the result
      await Future.delayed(const Duration(seconds: 2));

      return result.isReal;
    } catch (e, stackTrace) {
      debugPrint('[CameraAwesome] Processing error: $e');
      debugPrint('$stackTrace');
      if (mounted) {
        setState(() {
          _statusMessage = 'Error processing frame';
        });
      }
      return true; // On error, fallback to allow picture
    } finally {
      _isProcessing = false;
    }
  }

  void _takePicture(List<Face> faces) async {
    try {
      if (_photoCameraState == null) {
        return;
      }

      if(_isTakingPicture){
        return;
      }

      setState((){
        _isTakingPicture = true;
      });

      LoadingProgress.start(context);

      // if (widget.enableScreenReplayDetection) {
      //   setState(() {
      //     _finishProcessMessage = "Proses Anti-Spoof \nJangan gerakan kamera";
      //   });
      //   final isRealFace = await _performAntiSpoofingDetection(faces);
      //   if (!isRealFace) {
      //     LoadingProgress.stop(context);
      //     await _showSpoofingDetectedDialog();
      //     return;
      //   }
      // }

      setState((){
        _finishProcessMessage = "Pengambilan Foto";
      });

      await _photoCameraState!.sensorConfig.setAspectRatio(CameraAspectRatios.ratio_16_9);
      var result = await _photoCameraState!.takePhoto();

      if (widget.enableScreenReplayDetection) {
       setState(() {
         _finishProcessMessage = "Proses Anti-Spoof";
       });
        String? errorMsg = await _performAntiSpoofingDetectionFile(File(result.path!));
        if (errorMsg != null) {
          LoadingProgress.stop(context);
          await _showSpoofingDetectedDialog(errorMsg: errorMsg);
          return;
        }
      }

      LoadingProgress.stop(context);
      _onDetectionCompleted(imgToReturn: result.path);
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  void _onDetectionCompleted({
    String? imgToReturn,
  }) {
    final String? imgPath = imgToReturn;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => Navigator.pop(context, imgPath));
  }

  Widget _centerWidgetInRow(Widget wi, double width){
    return Row(
      children: [
        Expanded(
          flex: 1,
          child: Container(),
        ),
        SizedBox(width: width,
          child: Center(child: wi),
        ),
        Expanded(
          flex: 1,
          child: Container(),
        )
      ],
    );
  }

  Widget step(){

    var stepWidget = FlutterStepIndicator(
      height: 28,
      paddingLine: const EdgeInsets.symmetric(horizontal: 0),
      positiveColor: const Color.fromARGB(255, 0, 112, 224),
      progressColor: const Color(0xFFEA9C00),
      negativeColor: const Color(0xFFD5D5D5),
      padding: const EdgeInsets.all(4),
      list: list,
      division: _currentStep,
      onChange: (i) {},
      page: _currentStep,
      onClickItem: (p0) {

      },
    );

    var width = 30;
    var length = widget.steps.length;
    switch(length){
      case 1 :
        return _centerWidgetInRow(stepWidget, (width * length).toDouble());
      case 2 :
        return _centerWidgetInRow(stepWidget, (width + (width * (length * 2))).toDouble());
      case 3 :
        return _centerWidgetInRow(stepWidget, (width + (width * (length * 3))).toDouble());
      case 4 :
        return _centerWidgetInRow(stepWidget, (width + (width * (length * 2.5))).toDouble());
      case 5 :
        return stepWidget;
      default:
        return Container();
    }
  }

  Future _completeStep({
  required LivenessDetectionStep step,
  })async{
    if (mounted) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => setState((){
        _isProcessingStep = true;
        _isLoadingStep = true;
      }));

      await Future.delayed(
        const Duration(milliseconds: 250),
      );

      WidgetsBinding.instance
          .addPostFrameCallback((_) => setState((){
            if(_currentStep < steps.length - 1) {
              _currentStep++;
            } else {
              _isFinish = true;
            }
      }));

      await Future.delayed(
        const Duration(milliseconds: 750),
      );

      WidgetsBinding.instance
          .addPostFrameCallback((_) => setState((){
        _isProcessingStep = false;
        _isLoadingStep = false;
      }));
    }
  }

  _detect({
    required Face face,
    required LivenessDetectionStep step,
  }) async {
    if (_isProcessingStep) {
      return;
    }
    switch (step) {
      case LivenessDetectionStep.blink:
        final LivenessThresholdBlink? blinkThreshold =
        _thresholds
            .firstWhereOrNull(
              (p0) => p0 is LivenessThresholdBlink,
        ) as LivenessThresholdBlink?;
        if ((face.leftEyeOpenProbability ?? 1.0) <
            (blinkThreshold?.leftEyeProbability ?? 0.25) &&
            (face.rightEyeOpenProbability ?? 1.0) <
                (blinkThreshold?.rightEyeProbability ?? 0.25)) {
          await _completeStep(step: step);
        }
        break;
      case LivenessDetectionStep.turnRight:

        if(Platform.isIOS){
          final LivenessThresholdHead? headTurnThreshold =
          _thresholds
              .firstWhereOrNull(
                (p0) => p0 is LivenessThresholdHead,
          ) as LivenessThresholdHead?;
          if ((face.headEulerAngleY ?? 0) >
              (headTurnThreshold?.rotationAngle ?? 30)) {
            await _completeStep(step: step);
          }
          break;
        }

        final LivenessThresholdHead? headTurnThreshold =
        _thresholds
            .firstWhereOrNull(
              (p0) => p0 is LivenessThresholdHead,
        ) as LivenessThresholdHead?;
        if ((face.headEulerAngleY ?? 0) <
            (headTurnThreshold?.rotationAngle ?? -30)) {
          await _completeStep(step: step);
        }
        break;
      case LivenessDetectionStep.turnLeft:

        if(Platform.isIOS){
          final LivenessThresholdHead? headTurnThreshold =
          _thresholds
              .firstWhereOrNull(
                (p0) => p0 is LivenessThresholdHead,
          ) as LivenessThresholdHead?;
          if ((face.headEulerAngleY ?? 0) <
              (headTurnThreshold?.rotationAngle ?? -30)) {
            await _completeStep(step: step);
          }
          break;
        }

        final LivenessThresholdHead? headTurnThreshold =
        _thresholds
            .firstWhereOrNull(
              (p0) => p0 is LivenessThresholdHead,
        ) as LivenessThresholdHead?;
        if ((face.headEulerAngleY ?? 0) >
            (headTurnThreshold?.rotationAngle ?? 30)) {
          await _completeStep(step: step);
        }
        break;
      case LivenessDetectionStep.lookUp:
        final LivenessThresholdHead? headTurnThreshold =
        _thresholds
            .firstWhereOrNull(
              (p0) => p0 is LivenessThresholdHead,
        ) as LivenessThresholdHead?;
        if ((face.headEulerAngleX ?? 0) >
            (headTurnThreshold?.rotationAngle ?? 20)) {
          await _completeStep(step: step);
        }
        break;
      case LivenessDetectionStep.lookDown:
        final LivenessThresholdHead? headTurnThreshold =
        _thresholds
            .firstWhereOrNull(
              (p0) => p0 is LivenessThresholdHead,
        ) as LivenessThresholdHead?;
        if ((face.headEulerAngleX ?? 0) <
            (headTurnThreshold?.rotationAngle ?? -20)) {
          await _completeStep(step: step);
        }
        break;
      case LivenessDetectionStep.smile:
        final LivenessThresholdSmile? smileThreshold =
        _thresholds
            .firstWhereOrNull(
              (p0) => p0 is LivenessThresholdSmile,
        ) as LivenessThresholdSmile?;
        if ((face.smilingProbability ?? 0) >
            (smileThreshold?.probability ?? 0.75)) {
          await _completeStep(step: step);
        }
        break;
    }
  }

  Widget stepWidget(){
    if(_isFinish){
      return Align(
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 400,),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15)
                ),
                width: 100.0, // Adjust width as needed
                height: 50.0, // Adjust height as needed
                child: Center(child: Text(_finishProcessMessage, style: GoogleFonts.workSans(fontSize: 20),textAlign: TextAlign.justify, )),
              ),
            ),
          ],
        ),
      );
    }
    return Align(
      alignment: Alignment.bottomCenter,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 80,
            child: AbsorbPointer(
              absorbing: true,
              child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 30),
                  padding: const EdgeInsets.all(10),
                  child: _actionBox(steps[_currentStep].title)),
            ),
          ),
          const SizedBox(height: 10,),
          SizedBox(height: 40,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: step(),
            ),
          ),
          const SizedBox(height: 30,)
        ],
      ),
    );
  }

  Widget _actionBox(String text){
    return ClipRRect(
      borderRadius: BorderRadius.circular(12.0), // Adjust as needed
      child: Container(
        alignment: Alignment.center,
        width: 100.0, // Adjust width as needed
        height: 70.0, // Adjust height as needed
        color: Colors.white, // Adjust opacity and color as needed
        child: Center(
          child: Text(
            text,
            style: GoogleFonts.workSans(color: const Color.fromARGB(255, 0, 112, 224), fontSize: 18),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _isLoading ? Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.blueAccent),),):
      Stack(
        children: [
          CameraAwesomeBuilder.custom(
            saveConfig: SaveConfig.photoAndVideo(
              videoOptions: VideoOptions(enableAudio: false)
            ),
            previewFit: CameraPreviewFit.contain,
            sensorConfig: SensorConfig.single(
              sensor: Sensor.position(SensorPosition.front),
              aspectRatio: CameraAspectRatios.ratio_16_9,
              zoom: 0.0,
            ),
            onImageForAnalysis: (img) => _analyzeImage(img),
            imageAnalysisConfig: AnalysisConfig(
              androidOptions: const AndroidAnalysisOptions.nv21(
                width: 250,
              ),
              maxFramesPerSecond: 5,
            ),
            builder: (state, preview) {
              _preview = preview;
              state.when(
                onPreparingCamera: (state) => const Center(child: CircularProgressIndicator()),
                onPhotoMode: (state) => _photoCameraState = state,);
              return IgnorePointer(
                child: StreamBuilder(
                  stream: state.sensorConfig$,
                  builder: (_, snapshot) {
                    if (!snapshot.hasData) {
                      return Center(
                        child: Text("HP Anda tidak dapat melakukan Detect Face", style: GoogleFonts.workSans(fontSize: 20, color: Colors.orangeAccent),),
                      );
                    }else if (snapshot.hasError){
                      return Center(
                        child: Text("Error : ${snapshot.error}", style: GoogleFonts.workSans(fontSize: 20, color: Colors.orangeAccent),),
                      );
                    } else {
                      return StreamBuilder<FaceDetectionModel>(
                        stream: _faceDetectionController,
                        builder: (_, faceModelSnapshot) {
                          if (!faceModelSnapshot.hasData) {
                            return  Center(
                              child: Text("Wajah tidak terdeteksi", style: GoogleFonts.workSans(fontSize: 20, color: Colors.orangeAccent),),
                            );
                          }

                          if(faceModelSnapshot.data!.faces.isEmpty) {
                            return  Center(
                              child: Text("Wajah tidak ditemukan", style: GoogleFonts.workSans(fontSize: 20, color: Colors.orangeAccent),),
                            );
                          }

                          _processImage(faceModelSnapshot.data!.faces);

                          final canvasTransformation = faceModelSnapshot.data!.img
                              ?.getCanvasTransformation(_preview!);

                          return CustomPaint(
                            painter: FaceDetectorPainter(
                              model: faceModelSnapshot.requireData,
                              canvasTransformation: canvasTransformation,
                              preview: _preview!,
                            ),
                          );
                        },
                      );
                    }
                  },
                ),
              );
            },
          ),
          Positioned(
            bottom: 30,
            child: SizedBox(
              height: MediaQuery.of(context).size.height,
              width: MediaQuery.of(context).size.width,
              child: Stack(
                children: [
                  stepWidget(),
                  Visibility(
                    visible: _isLoadingStep,
                    child: Center(
                      child: LoadingAnimationWidget.staggeredDotsWave(
                        color: const Color.fromARGB(255, 0, 112, 224),
                        size: 80,
                      ),
                    ),
                  ),
                ],
              )
            ),
          ),
          Positioned(
            top: 50,
            left: 20,
            child: Material(
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                },
                child: Container(
                  height: 50,
                  width: 50,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.4),
                        spreadRadius: 2,
                        blurRadius: 7,
                        offset: const Offset(0, 3), // changes position of shadow
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.clear, size: 40,),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future _analyzeImage(AnalysisImage img) async {
    final inputImage = img.toInputImage();

    try {
      _faceDetectionController.add(
        FaceDetectionModel(
          faces: await faceDetector.processImage(inputImage),
          absoluteImageSize: inputImage.metadata!.size,
          rotation: 0,
          imageRotation: img.inputImageRotation,
          img: img,
        ),
      );
      // debugPrint("...sending image resulted with : ${faces?.length} faces");
    } catch (error) {
      debugPrint("...sending image resulted error $error");
    }
  }
}

class FaceDetectorPainter extends CustomPainter {
  final FaceDetectionModel model;
  final CanvasTransformation? canvasTransformation;
  final AnalysisPreview? preview;

  FaceDetectorPainter({
    required this.model,
    this.canvasTransformation,
    this.preview,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (preview == null || model.img == null) {
      return;
    }

    var color = Colors.white;

    // We apply the canvas transformation to the canvas so that the barcode
    // rect is drawn in the correct orientation. (Android only)
    if (canvasTransformation != null) {
      canvas.save();
      canvas.applyTransformation(canvasTransformation!, size);
    }
    for (final Face face in model.faces) {
      Map<FaceContourType, Path> paths = {
        for (var fct in FaceContourType.values) fct: Path()
      };
      face.contours.forEach((contourType, faceContour) {
        if (faceContour != null) {
          paths[contourType]!.addPolygon(
              faceContour.points
                  .map(
                    (element) => preview!.convertFromImage(
                  Offset(element.x.toDouble(), element.y.toDouble()),
                  model.img!,
                ),
              )
                  .toList(),
              true);
        }
      });
      paths.removeWhere((key, value) => value.getBounds().isEmpty);
      for (var p in paths.entries) {
        canvas.drawPath(
            p.value,
            Paint()
              ..color = color
              ..strokeWidth = 0.3
              ..style = PaintingStyle.stroke);
      }
    }
    // if you want to draw without canvas transformation, use this:
    if (canvasTransformation != null) {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(FaceDetectorPainter oldDelegate) {
    return oldDelegate.model != model;
  }
}

extension InputImageRotationConversion on InputImageRotation {
  double toRadians() {
    final degrees = toDegrees();
    return degrees * 2 * pi / 360;
  }

  int toDegrees() {
    switch (this) {
      case InputImageRotation.rotation0deg:
        return 0;
      case InputImageRotation.rotation90deg:
        return 90;
      case InputImageRotation.rotation180deg:
        return 180;
      case InputImageRotation.rotation270deg:
        return 270;
    }
  }
}

class FaceDetectionModel {
  final List<Face> faces;
  final Size absoluteImageSize;
  final int rotation;
  final InputImageRotation imageRotation;
  final AnalysisImage? img;

  FaceDetectionModel({
    required this.faces,
    required this.absoluteImageSize,
    required this.rotation,
    required this.imageRotation,
    this.img,
  });

  Size get croppedSize => img!.croppedSize;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is FaceDetectionModel &&
              runtimeType == other.runtimeType &&
              faces == other.faces &&
              absoluteImageSize == other.absoluteImageSize &&
              rotation == other.rotation &&
              imageRotation == other.imageRotation &&
              croppedSize == other.croppedSize;

  @override
  int get hashCode =>
      faces.hashCode ^
      absoluteImageSize.hashCode ^
      rotation.hashCode ^
      imageRotation.hashCode ^
      croppedSize.hashCode;
}

class SimpleFaceDetectorPainter extends CustomPainter {
  final List<Face> faces;
  final CanvasTransformation? canvasTransformation;
  final AnalysisPreview? preview;
  final AnalysisImage? img;
  final DetectionResult? detectionResult;

  SimpleFaceDetectorPainter({
    required this.faces,
    this.canvasTransformation,
    this.preview,
    this.img,
    this.detectionResult,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (preview == null || img == null) {
      return;
    }

    // Apply canvas transformation (Android only)
    if (canvasTransformation != null) {
      canvas.save();
      canvas.applyTransformation(canvasTransformation!, size);
    }

    for (final Face face in faces) {
      // Determine color based on detection result
      Color boxColor = Colors.white;
      if (detectionResult != null) {
        boxColor = detectionResult!.isReal ? Colors.green : Colors.red;
      }

      // Draw bounding box only (no contours for performance)
      final boundingBox = face.boundingBox;
      final rect = Rect.fromLTRB(
        preview!.convertFromImage(
          Offset(boundingBox.left, boundingBox.top),
          img!,
        ).dx,
        preview!.convertFromImage(
          Offset(boundingBox.left, boundingBox.top),
          img!,
        ).dy,
        preview!.convertFromImage(
          Offset(boundingBox.right, boundingBox.bottom),
          img!,
        ).dx,
        preview!.convertFromImage(
          Offset(boundingBox.right, boundingBox.bottom),
          img!,
        ).dy,
      );

      // Draw rectangle with rounded corners
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        Paint()
          ..color = boxColor
          ..strokeWidth = 4.0
          ..style = PaintingStyle.stroke,
      );

      // Draw corner accents
      _drawCornerAccents(canvas, rect, boxColor);
    }

    if (canvasTransformation != null) {
      canvas.restore();
    }
  }

  void _drawCornerAccents(Canvas canvas, Rect rect, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 6.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const double cornerLength = 30.0;

    // Top-left
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(cornerLength, 0), paint);
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(0, cornerLength), paint);

    // Top-right
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(-cornerLength, 0), paint);
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(0, cornerLength), paint);

    // Bottom-left
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(cornerLength, 0), paint);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(0, -cornerLength), paint);

    // Bottom-right
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(-cornerLength, 0), paint);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(0, -cornerLength), paint);
  }

  @override
  bool shouldRepaint(SimpleFaceDetectorPainter oldDelegate) {
    return oldDelegate.faces != faces ||
        oldDelegate.detectionResult != detectionResult;
  }
}