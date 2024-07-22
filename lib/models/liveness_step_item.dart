import 'dart:convert';

import 'package:flutter_liveness_detection/models/liveness_detection_step.dart';

class LivenessDetectionStepItem {
  final LivenessDetectionStep step;
  final String title;
  final double? thresholdToCheck;
  final bool isCompleted;

  LivenessDetectionStepItem({
    required this.step,
    required this.title,
    this.thresholdToCheck,
    required this.isCompleted,
  });

  LivenessDetectionStepItem copyWith({
    LivenessDetectionStep? step,
    String? title,
    double? thresholdToCheckm,
    bool? isCompleted,
  }) {
    return LivenessDetectionStepItem(
      step: step ?? this.step,
      title: title ?? this.title,
      thresholdToCheck: thresholdToCheck ?? this.thresholdToCheck,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
  Map<String, dynamic> toMap() {
    final result = <String, dynamic>{};

    result.addAll({'step': step.index});
    result.addAll({'title': title});
    if (thresholdToCheck != null) {
      result.addAll({'thresholdToCheck': thresholdToCheck});
    }
    result.addAll({'isCompleted': isCompleted});

    return result;
  }

  factory LivenessDetectionStepItem.fromMap(Map<String, dynamic> map) {
    return LivenessDetectionStepItem(
      step: LivenessDetectionStep.values[map['step'] ?? 0],
      title: map['title'] ?? '',
      thresholdToCheck: map['thresholdToCheck']?.toDouble(),
      isCompleted: map['isCompleted'] ?? false,
    );
  }

  String toJson() => json.encode(toMap());

  factory LivenessDetectionStepItem.fromJson(String source) =>
      LivenessDetectionStepItem.fromMap(json.decode(source));

  @override
  String toString() {
    return 'Liveness Detection (step: $step, title: $title, thresholdToCheck: $thresholdToCheck, isCompleted: $isCompleted)';
  }

    @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is LivenessDetectionStepItem &&
        other.step == step &&
        other.title == title &&
        other.thresholdToCheck == thresholdToCheck &&
        other.isCompleted == isCompleted;
  }

  @override
  int get hashCode {
    return step.hashCode ^
        title.hashCode ^
        thresholdToCheck.hashCode ^
        isCompleted.hashCode;
  }
}
