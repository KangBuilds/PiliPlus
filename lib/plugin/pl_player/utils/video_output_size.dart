import 'dart:math' as math;

import 'package:flutter/painting.dart';

Size calculateVideoOutputSize({
  required Size viewport,
  required Size source,
  required double devicePixelRatio,
  required BoxFit fit,
  double? aspectRatio,
}) {
  if (viewport.isEmpty || source.isEmpty || devicePixelRatio <= 0) {
    return Size.zero;
  }

  final ratio = aspectRatio ?? source.aspectRatio;
  final sourceInLogicalPixels = Size(
    source.height / devicePixelRatio * ratio,
    source.height / devicePixelRatio,
  );
  final fitted = applyBoxFit(fit, sourceInLogicalPixels, viewport).destination;
  final target = Size(
    fitted.width * devicePixelRatio,
    fitted.height * devicePixelRatio,
  );
  final scale = math.min(
    1.0,
    math.min(source.width / target.width, source.height / target.height),
  );

  return Size(
    (target.width * scale).round().clamp(1, source.width.floor()).toDouble(),
    (target.height * scale).round().clamp(1, source.height.floor()).toDouble(),
  );
}
