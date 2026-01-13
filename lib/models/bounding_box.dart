import 'dart:ui';

class BoundingBox {
  final int x;
  final int y;
  final int width;
  final int height;

  BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  BoundingBox.fromRect(Rect rect)
      : x = rect.left.toInt(),
        y = rect.top.toInt(),
        width = rect.width.toInt(),
        height = rect.height.toInt();

  Rect toRect() => Rect.fromLTWH(
    x.toDouble(),
    y.toDouble(),
    width.toDouble(),
    height.toDouble(),
  );

  @override
  String toString() => 'BoundingBox(x: $x, y: $y, w: $width, h: $height)';
}