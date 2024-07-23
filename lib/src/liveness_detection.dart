import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:camerawesome/pigeon.dart';
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_liveness_detection/models/liveness_detection_step.dart';
import 'package:flutter_liveness_detection/models/liveness_step_item.dart';
import 'package:flutter_liveness_detection/models/liveness_threshold.dart';
import 'package:flutter_liveness_detection/src/liveness_detection_steps_overlay.dart';
import 'package:flutter_liveness_detection/utils/mlkit_utils.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:rxdart/rxdart.dart';
import 'package:collection/collection.dart';
import 'package:loading_progress/loading_progress.dart';


class LivenessDetection extends StatefulWidget {

  final List<LivenessDetectionStepItem> steps;
  final List<LivenessThreshold>? thresholds;

  const LivenessDetection({super.key, required this.steps, this.thresholds});

  @override
  State<LivenessDetection> createState() => _LivenessDetectionState();
}

class _LivenessDetectionState extends State<LivenessDetection> {


  final GlobalKey<LivenessDetectionStepOverlayState> _stepsKey =
  GlobalKey<LivenessDetectionStepOverlayState>();

  late bool _isInfoStepCompleted;
  late final List<LivenessDetectionStepItem> steps;
  final _faceDetectionController = BehaviorSubject<FaceDetectionModel>();
  Preview? _preview;
  PhotoCameraState? _photoCameraState;

  bool _isProcessingStep = false;
  bool _didCloseEyes = false;
  bool _isTakingPicture = false;
  bool _notifTakingPicture = false;

  List<LivenessThreshold> _thresholds = [];

  Timer? _timerToDetectFace;


  final options = FaceDetectorOptions(
    enableContours: true,
    enableClassification: true,
  );
  late final faceDetector = FaceDetector(options: options);

  @override
  void initState() {
    _preInitCallBack();
    super.initState();
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

  void _preInitCallBack() {
    steps = widget.steps;
    if(widget.thresholds != null) _thresholds = widget.thresholds!;
  }

  void _startFaceDetectionTimer() {
    // Create a Timer that runs for 45 seconds and calls _onDetectionCompleted after that.
    _timerToDetectFace = Timer(const Duration(minutes: 1, seconds: 30), () {
      _onDetectionCompleted(imgToReturn: null); // Pass null or "" as needed.
    });
  }

  Future<void> _processImage(List<Face> faces) async{
    if (faces.isEmpty) {
      _resetSteps();
    }else{
      if (_isProcessingStep &&
          steps[_stepsKey.currentState?.currentIndex ?? 0].step ==
              LivenessDetectionStep.blink) {
        if (_didCloseEyes) {
          if ((faces.first.leftEyeOpenProbability ?? 1.0) < 0.75 &&
              (faces.first.rightEyeOpenProbability ?? 1.0) < 0.75) {
            await _completeStep(
              step: steps[_stepsKey.currentState?.currentIndex ?? 0].step,
            );
          }
        }
      }
      _detect(
        face: faces.first,
        step: steps[_stepsKey.currentState?.currentIndex ?? 0].step,
      );
    }
  }

  Future<void> _completeStep({
    required LivenessDetectionStep step,
  }) async {
    final int indexToUpdate = steps.indexWhere(
          (p0) => p0.step == step,
    );

    steps[indexToUpdate] = steps[indexToUpdate].copyWith(
      isCompleted: true,
    );
    if (mounted) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => setState((){}));
    }
    await _stepsKey.currentState?.nextPage();
    _stopProcessing();
  }

  void _stopProcessing() {
    if (!mounted) {
      return;
    }
    WidgetsBinding.instance
        .addPostFrameCallback((_) => setState(
          () => _isProcessingStep = false,
    ));
  }

  void _startProcessing() {
    if (!mounted) {
      return;
    }
    WidgetsBinding.instance
        .addPostFrameCallback((_) => setState(
          () => _isProcessingStep = true,
    ));
  }

  void _resetSteps() async {
    for (var p0 in steps) {
      final int index = steps.indexWhere(
            (p1) => p1.step == p0.step,
      );
      steps[index] = steps[index].copyWith(
        isCompleted: false,
      );
    }

    _didCloseEyes = false;
    if (_stepsKey.currentState?.currentIndex != 0) {
      _stepsKey.currentState?.reset();
    }
    if (mounted) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => setState((){}));
    }
  }

  void _takePicture() async {
    try {

      if (_isTakingPicture || _photoCameraState == null) {
        return;
      }
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _isTakingPicture = true);
      LoadingProgress.start(context);
      await _photoCameraState!.sensorConfig.setAspectRatio(CameraAspectRatios.ratio_16_9);
      //await _photoCameraState!.cameraContext.sensorConfig.setAspectRatio(CameraAspectRatios.ratio_16_9);
      var result = await _photoCameraState!.takePhoto();
      LoadingProgress.stop(context);
      _onDetectionCompleted(imgToReturn: result.path);
    } catch (e) {
      print(e);
    }
  }

  void _onDetectionCompleted({
    String? imgToReturn,
  }) {
    print(imgToReturn);
    final String? imgPath = imgToReturn;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => Navigator.pop(context, imgPath));
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
          _startProcessing();
          if (mounted) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => setState(
                  () => _didCloseEyes = true,
            ));
          }
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
            _startProcessing();
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
          _startProcessing();
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
            _startProcessing();
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
          _startProcessing();
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
          _startProcessing();
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
          _startProcessing();
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
          _startProcessing();
          await _completeStep(step: step);
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
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
                      return const SizedBox();
                    } else {
                      return StreamBuilder<FaceDetectionModel>(
                        stream: _faceDetectionController,
                        builder: (_, faceModelSnapshot) {
                          if (!faceModelSnapshot.hasData) return const SizedBox();
                          // this is the transformation needed to convert the image to the preview
                          // Android mirrors the preview but the analysis image is not

                          _processImage(faceModelSnapshot.data!.faces);

                          return Container();
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
              child: LivenessDetectionStepOverlay(
                  key: _stepsKey,
                  steps: steps,
                  onCompleted: () => Future.delayed(
                    const Duration(milliseconds: 500),
                        () => _takePicture(),
                  ),
                  onTakingPicture: () {
                    _notifTakingPicture = true;
                  }
              ),
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
  final Preview? preview;

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
          // for (var element in faceContour.points) {
          //   var position = preview!.convertFromImage(
          //     Offset(element.x.toDouble(), element.y.toDouble()),
          //     model.img!,
          //   );
          //   canvas.drawCircle(
          //     position,
          //     4,
          //     Paint()..color = Colors.blue,
          //   );
          // }
        }
      });
      paths.removeWhere((key, value) => value.getBounds().isEmpty);
      for (var p in paths.entries) {
        canvas.drawPath(
            p.value,
            Paint()
              ..color = Colors.white
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