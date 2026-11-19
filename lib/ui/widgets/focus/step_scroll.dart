import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

void revealInNearestScrollable(
  BuildContext context, {
  required double alignment,
  Duration duration = const Duration(milliseconds: 200),
  Curve curve = Curves.easeOut,
}) {
  final scrollable = Scrollable.maybeOf(context);
  final renderObject = context.findRenderObject();
  if (scrollable == null || renderObject is! RenderBox) return;
  final position = scrollable.position;
  final target = RenderAbstractViewport.of(renderObject)
      .getOffsetToReveal(renderObject, alignment)
      .offset
      .clamp(position.minScrollExtent, position.maxScrollExtent)
      .toDouble();
  unawaited(position.animateTo(target, duration: duration, curve: curve));
}
