import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

enum RefreshSlot { body, indicator }

class RefreshLayout
    extends SlottedMultiChildRenderObjectWidget<RefreshSlot, RenderBox> {
  const RefreshLayout({
    super.key,
    required this.position,
    required this.scale,
    required this.displacement,
    required this.edgeOffset,
    required this.body,
    this.indicator,
  });

  final Animation<double> position;
  final Animation<double> scale;
  final double displacement;
  final double edgeOffset;
  final Widget body;
  final Widget? indicator;

  @override
  Iterable<RefreshSlot> get slots => RefreshSlot.values;

  @override
  Widget? childForSlot(RefreshSlot slot) => switch (slot) {
    .body => body,
    .indicator => indicator,
  };

  @override
  RenderRefreshLayout createRenderObject(BuildContext context) =>
      RenderRefreshLayout(position, scale, displacement, edgeOffset);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderRefreshLayout renderObject,
  ) {
    renderObject.update(position, scale, displacement, edgeOffset);
  }
}

class RenderRefreshLayout extends RenderBox
    with SlottedContainerRenderObjectMixin<RefreshSlot, RenderBox> {
  RenderRefreshLayout(
    this._position,
    this._scale,
    this._displacement,
    this._edgeOffset,
  );

  Animation<double> _position;
  Animation<double> _scale;
  double _displacement;
  double _edgeOffset;
  final _clipLayer = LayerHandle<ClipRectLayer>();
  final _transformLayer = LayerHandle<TransformLayer>();

  void update(
    Animation<double> position,
    Animation<double> scale,
    double displacement,
    double edgeOffset,
  ) {
    if (_position == position &&
        _scale == scale &&
        _displacement == displacement &&
        _edgeOffset == edgeOffset) {
      return;
    }
    if (attached) _removeListeners();
    _position = position;
    _scale = scale;
    _displacement = displacement;
    _edgeOffset = edgeOffset;
    if (attached) _addListeners();
    _animationChanged();
  }

  void _animationChanged() {
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  void _addListeners() {
    _position.addListener(_animationChanged);
    _scale.addListener(_animationChanged);
  }

  void _removeListeners() {
    _position.removeListener(_animationChanged);
    _scale.removeListener(_animationChanged);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _addListeners();
  }

  @override
  void detach() {
    _removeListeners();
    super.detach();
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    _transformLayer.layer = null;
    super.dispose();
  }

  RenderBox get _body => childForSlot(.body)!;
  RenderBox? get _indicator => childForSlot(.indicator);

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_body.getDryLayout(constraints.loosen()));

  @override
  void performLayout() {
    _body.layout(constraints.loosen(), parentUsesSize: true);
    size = constraints.constrain(_body.size);
    _indicator?.layout(
      BoxConstraints(maxWidth: size.width),
      parentUsesSize: true,
    );
  }

  Rect get _indicatorClip => Rect.fromLTWH(
    0,
    _edgeOffset,
    size.width,
    (_indicator!.size.height + _displacement) * _position.value,
  );

  Matrix4 get _indicatorTransform {
    final indicatorSize = _indicator!.size;
    final scale = _scale.value;
    // Keep the existing bottom-aligned reveal and paint-only shrinking.
    return Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(
      (size.width - indicatorSize.width * scale) / 2,
      _indicatorClip.bottom -
          indicatorSize.height +
          indicatorSize.height * (1 - scale) / 2,
      0,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.paintChild(_body, offset);
    final indicator = _indicator;
    if (indicator == null || _position.value <= 0 || _scale.value <= 0) {
      _clipLayer.layer = null;
      _transformLayer.layer = null;
      return;
    }
    _clipLayer.layer = context.pushClipRect(
      needsCompositing,
      offset,
      _indicatorClip,
      (context, offset) {
        _transformLayer.layer = context.pushTransform(
          needsCompositing,
          offset,
          _indicatorTransform,
          (context, offset) => context.paintChild(indicator, offset),
          oldLayer: _transformLayer.layer,
        );
      },
      oldLayer: _clipLayer.layer,
    );
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      child == _indicator ? _indicatorClip : null;

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (child == _indicator) transform.multiply(_indicatorTransform);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      _body.hitTest(result, position: position);
}
