import 'dart:typed_data';
import 'dart:math';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:camerawesome/camerawesome_plugin.dart';
import '../models/bounding_box.dart';

/// Image processor for MiniFASNet anti-spoofing
/// Based on Python implementation from Silent-Face-Anti-Spoofing
class ImageProcessor {
  static const int INPUT_SIZE = 80;

  /// Preprocess image untuk ONNX model
  /// Returns Float32List dengan shape [1, 3, 80, 80] in CHW format (BGR)
  static Float32List preprocessImage({
    required img.Image image,
    required BoundingBox bbox,
    required double scale,
  }) {
    // 1. Calculate expanded bounding box
    final expandedBox = _getExpandedBox(
      srcW: image.width,
      srcH: image.height,
      bbox: bbox,
      scale: scale,
    );

    // 2. Crop image dengan expanded bbox (include right-bottom boundary +1)
    final croppedImage = img.copyCrop(
      image,
      x: expandedBox.x,
      y: expandedBox.y,
      width: expandedBox.width + 1,
      height: expandedBox.height + 1,
    );

    // 3. Resize ke 80x80
    final resizedImage = img.copyResize(
      croppedImage,
      width: INPUT_SIZE,
      height: INPUT_SIZE,
      interpolation: img.Interpolation.linear,
    );

    // 4. Convert ke Float32List in CHW format (BGR)
    return _convertToCHW(resizedImage);
  }

  /// Calculate expanded bounding box
  /// Sama dengan Python version untuk konsistensi hasil
  static BoundingBox _getExpandedBox({
    required int srcW,
    required int srcH,
    required BoundingBox bbox,
    required double scale,
  }) {
    final x = bbox.x;
    final y = bbox.y;
    final boxW = bbox.width;
    final boxH = bbox.height;

    // Limit scale to image boundaries
    scale = min(
      (srcH - 1) / boxH,
      min((srcW - 1) / boxW, scale),
    );

    final newWidth = boxW * scale;
    final newHeight = boxH * scale;
    final centerX = boxW / 2 + x;
    final centerY = boxH / 2 + y;

    double leftTopX = centerX - newWidth / 2;
    double leftTopY = centerY - newHeight / 2;
    double rightBottomX = centerX + newWidth / 2;
    double rightBottomY = centerY + newHeight / 2;

    // Boundary handling: adjust opposite side to keep size
    if (leftTopX < 0) {
      rightBottomX -= leftTopX;
      leftTopX = 0;
    }

    if (leftTopY < 0) {
      rightBottomY -= leftTopY;
      leftTopY = 0;
    }

    if (rightBottomX > srcW - 1) {
      leftTopX -= (rightBottomX - srcW + 1);
      rightBottomX = srcW - 1;
    }

    if (rightBottomY > srcH - 1) {
      leftTopY -= (rightBottomY - srcH + 1);
      rightBottomY = srcH - 1;
    }

    return BoundingBox(
      x: leftTopX.toInt(),
      y: leftTopY.toInt(),
      width: (rightBottomX - leftTopX).toInt(),
      height: (rightBottomY - leftTopY).toInt(),
    );
  }

  /// Convert image to CHW format (Channel, Height, Width) in BGR
  /// PENTING: Model dilatih dengan BGR format, bukan RGB!
  static Float32List _convertToCHW(img.Image image) {
    final input = Float32List(3 * INPUT_SIZE * INPUT_SIZE);
    int idx = 0;

    // Channel 0: Blue
    for (int y = 0; y < INPUT_SIZE; y++) {
      for (int x = 0; x < INPUT_SIZE; x++) {
        final pixel = image.getPixel(x, y);
        input[idx++] = pixel.b.toDouble();
      }
    }

    // Channel 1: Green
    for (int y = 0; y < INPUT_SIZE; y++) {
      for (int x = 0; x < INPUT_SIZE; x++) {
        final pixel = image.getPixel(x, y);
        input[idx++] = pixel.g.toDouble();
      }
    }

    // Channel 2: Red
    for (int y = 0; y < INPUT_SIZE; y++) {
      for (int x = 0; x < INPUT_SIZE; x++) {
        final pixel = image.getPixel(x, y);
        input[idx++] = pixel.r.toDouble();
      }
    }

    return input;
  }

  /// Convert camerawesome AnalysisImage to img.Image (Optimized with isolate)
  /// Simple and robust conversion supporting multiple formats
  static Future<img.Image?> convertFromAnalysisImageAsync(AnalysisImage analysisImage) async {
    try {
      final format = analysisImage.format;

      if (format == InputAnalysisImageFormat.nv21) {
        // Android NV21 format - use compute for background processing
        Uint8List? bytes;
        analysisImage.when(
          nv21: (nv21) => bytes = nv21.bytes,
          bgra8888: (_) => null,
          yuv420: (_) => null,
          jpeg: (_) => null,
        );

        if (bytes == null) return null;

        // Run conversion in isolate for better performance
        return await compute(_convertNV21Isolate, _NV21Data(
          bytes: bytes!,
          width: analysisImage.width,
          height: analysisImage.height,
        ));
      } else if (format == InputAnalysisImageFormat.bgra8888) {
        return _convertBGRA(analysisImage);
      } else if (format == InputAnalysisImageFormat.yuv_420) {
        return _convertYUV420(analysisImage);
      } else if (format == InputAnalysisImageFormat.jpeg) {
        return _convertJPEG(analysisImage);
      } else {
        print('[ImageProcessor] Unsupported format: $format');
        return null;
      }
    } catch (e) {
      print('[ImageProcessor] Error converting analysis image: $e');
      return null;
    }
  }

  /// Synchronous version (for backward compatibility)
  static img.Image? convertFromAnalysisImage(AnalysisImage analysisImage) {
    try {
      final format = analysisImage.format;

      if (format == InputAnalysisImageFormat.nv21) {
        return _convertNV21(analysisImage);
      } else if (format == InputAnalysisImageFormat.bgra8888) {
        return _convertBGRA(analysisImage);
      } else if (format == InputAnalysisImageFormat.yuv_420) {
        return _convertYUV420(analysisImage);
      } else if (format == InputAnalysisImageFormat.jpeg) {
        return _convertJPEG(analysisImage);
      } else {
        print('[ImageProcessor] Unsupported format: $format');
        return null;
      }
    } catch (e) {
      print('[ImageProcessor] Error converting analysis image: $e');
      return null;
    }
  }

  /// Isolate worker for NV21 conversion
  static img.Image _convertNV21Isolate(_NV21Data data) {
    return _convertNV21ToImage(data.bytes, data.width, data.height);
  }

  /// Convert NV21 bytes to img.Image (shared by sync and async methods)
  static img.Image _convertNV21ToImage(
    Uint8List bytes,
    int width,
    int height,
  ) {
    final rgbImage = img.Image(width: width, height: height);
    final ySize = width * height;

    for (int row = 0; row < height; row++) {
      for (int col = 0; col < width; col++) {
        final yIndex = row * width + col;
        final uvIndex = ySize + (row ~/ 2) * width + (col & ~1);

        final y = bytes[yIndex] & 0xff;
        final v = (bytes[uvIndex] & 0xff) - 128;
        final u = (bytes[uvIndex + 1] & 0xff) - 128;

        // YUV to RGB conversion
        int r = (y + 1.402 * v).round().clamp(0, 255);
        int g = (y - 0.344136 * u - 0.714136 * v).round().clamp(0, 255);
        int b = (y + 1.772 * u).round().clamp(0, 255);

        rgbImage.setPixelRgba(col, row, r, g, b, 255);
      }
    }

    return rgbImage;
  }

  /// Convert NV21 format (Android)
  static img.Image? _convertNV21(AnalysisImage analysisImage) {
    try {
      // Get bytes using when() method
      Uint8List? bytes;
      analysisImage.when(
        nv21: (nv21) => bytes = nv21.bytes,
        bgra8888: (_) => null,
        yuv420: (_) => null,
        jpeg: (_) => null,
      );

      if (bytes == null) return null;

      return _convertNV21ToImage(
        bytes!,
        analysisImage.width,
        analysisImage.height,
      );
    } catch (e) {
      print('[ImageProcessor] NV21 conversion error: $e');
      return null;
    }
  }

  /// Convert BGRA format (iOS)
  static img.Image? _convertBGRA(AnalysisImage analysisImage) {
    try {
      Uint8List? bytes;
      analysisImage.when(
        nv21: (_) => null,
        bgra8888: (bgra) => bytes = bgra.bytes,
        yuv420: (_) => null,
        jpeg: (_) => null,
      );

      if (bytes == null) return null;

      return img.Image.fromBytes(
        width: analysisImage.width,
        height: analysisImage.height,
        bytes: bytes!.buffer,
        order: img.ChannelOrder.bgra,
      );
    } catch (e) {
      print('[ImageProcessor] BGRA conversion error: $e');
      return null;
    }
  }

  /// Convert YUV420 format
  static img.Image? _convertYUV420(AnalysisImage analysisImage) {
    try {
      dynamic planes;
      analysisImage.when(
        nv21: (_) => null,
        bgra8888: (_) => null,
        yuv420: (yuv) => planes = yuv.planes,
        jpeg: (_) => null,
      );

      if (planes == null || planes.length < 3) return null;

      final width = analysisImage.width;
      final height = analysisImage.height;
      final rgbImage = img.Image(width: width, height: height);

      final yPlane = planes[0].bytes;
      final uPlane = planes[1].bytes;
      final vPlane = planes[2].bytes;

      final uvRowStride = planes[1].bytesPerRow;
      final uvPixelStride = planes[1].bytesPerPixel;

      for (int row = 0; row < height; row++) {
        for (int col = 0; col < width; col++) {
          final yIndex = row * planes[0].bytesPerRow + col;
          final uvIndex = (row ~/ 2) * uvRowStride + (col ~/ 2) * uvPixelStride;

          final y = yPlane[yIndex] & 0xff;
          final u = (uPlane[uvIndex] & 0xff) - 128;
          final v = (vPlane[uvIndex] & 0xff) - 128;

          // YUV to RGB conversion
          int r = (y + 1.402 * v).round().clamp(0, 255);
          int g = (y - 0.344136 * u - 0.714136 * v).round().clamp(0, 255);
          int b = (y + 1.772 * u).round().clamp(0, 255);

          rgbImage.setPixelRgba(col, row, r, g, b, 255);
        }
      }

      return rgbImage;
    } catch (e) {
      print('[ImageProcessor] YUV420 conversion error: $e');
      return null;
    }
  }

  /// Convert JPEG format
  static img.Image? _convertJPEG(AnalysisImage analysisImage) {
    try {
      Uint8List? bytes;
      analysisImage.when(
        nv21: (_) => null,
        bgra8888: (_) => null,
        yuv420: (_) => null,
        jpeg: (jpeg) => bytes = jpeg.bytes,
      );

      if (bytes == null) return null;

      return img.decodeJpg(bytes!);
    } catch (e) {
      print('[ImageProcessor] JPEG conversion error: $e');
      return null;
    }
  }
}

/// Helper class for passing data to isolate
class _NV21Data {
  final Uint8List bytes;
  final int width;
  final int height;

  _NV21Data({
    required this.bytes,
    required this.width,
    required this.height,
  });
}
