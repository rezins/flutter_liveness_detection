import 'package:flutter/material.dart';
import 'package:flutter_liveness_detection/models/bounding_box.dart';

class DetectionResult {
  final int label;
  final String labelText;
  final bool isReal;
  final double confidence;
  final Map<String, double> scores;
  final BoundingBox? boundingBox;
  final DateTime timestamp;

  DetectionResult({
    required this.label,
    required this.labelText,
    required this.isReal,
    required this.confidence,
    required this.scores,
    this.boundingBox,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Label names: 0=paper, 1=real, 2=screen
  static const List<String> labelNames = [
    "Paper Photo",
    "Real Face",
    "Screen Photo"
  ];

  Color get statusColor => isReal ? Colors.green : Colors.red;
  String get statusText => isReal ? "REAL" : "FAKE";

  @override
  String toString() {
    return 'DetectionResult(label: $labelText, confidence: ${confidence.toStringAsFixed(3)}, isReal: $isReal)';
  }
}