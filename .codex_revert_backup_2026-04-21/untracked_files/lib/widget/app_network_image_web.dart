// ignore_for_file: undefined_prefixed_name

import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

int _nextNetworkImageId = 0;

class AppNetworkImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final Alignment alignment;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final int? cacheHeight;
  final Widget fallback;
  final bool gaplessPlayback;

  const AppNetworkImage({
    super.key,
    required this.url,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.width,
    this.height,
    this.cacheWidth,
    this.cacheHeight,
    this.gaplessPlayback = false,
  });

  @override
  State<AppNetworkImage> createState() => _AppNetworkImageState();
}

class _AppNetworkImageState extends State<AppNetworkImage> {
  late final String _viewType;
  late final html.ImageElement _imageElement;
  StreamSubscription<html.Event>? _loadSub;
  StreamSubscription<html.Event>? _errorSub;
  bool _hasError = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'app-network-image-${_nextNetworkImageId++}';
    _imageElement = html.ImageElement();
    _bindEvents();
    _updateImageElement();
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      return _imageElement;
    });
  }

  @override
  void didUpdateWidget(covariant AppNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.fit != widget.fit ||
        oldWidget.alignment != widget.alignment) {
      _updateImageElement();
    }
  }

  void _bindEvents() {
    _loadSub = _imageElement.onLoad.listen((_) {
      if (!mounted || _disposed) return;
      if (_hasError) {
        setState(() => _hasError = false);
      }
    });
    _errorSub = _imageElement.onError.listen((_) {
      if (!mounted || _disposed) return;
      setState(() => _hasError = true);
    });
  }

  void _updateImageElement() {
    if (_disposed) return;
    final url = widget.url.trim();
    _hasError = url.isEmpty;
    _imageElement
      ..src = url
      ..alt = ''
      ..draggable = false
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = '0'
      ..style.margin = '0'
      ..style.padding = '0'
      ..style.display = 'block'
      ..style.pointerEvents = 'none'
      ..style.userSelect = 'none'
      ..style.objectFit = _cssFit(widget.fit)
      ..style.objectPosition = _cssAlignment(widget.alignment);
  }

  String _cssFit(BoxFit fit) {
    switch (fit) {
      case BoxFit.contain:
        return 'contain';
      case BoxFit.fill:
        return 'fill';
      case BoxFit.none:
        return 'none';
      case BoxFit.scaleDown:
        return 'scale-down';
      case BoxFit.fitHeight:
      case BoxFit.fitWidth:
      case BoxFit.cover:
        return 'cover';
    }
  }

  String _cssAlignment(Alignment alignment) {
    final x = ((alignment.x + 1) / 2 * 100).clamp(0, 100).toStringAsFixed(0);
    final y = ((alignment.y + 1) / 2 * 100).clamp(0, 100).toStringAsFixed(0);
    return '$x% $y%';
  }

  @override
  void dispose() {
    _disposed = true;
    _loadSub?.cancel();
    _errorSub?.cancel();
    _imageElement
      ..src = ''
      ..remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.url.trim().isEmpty || _hasError) {
      return widget.fallback;
    }
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: IgnorePointer(
        ignoring: true,
        child: HtmlElementView(viewType: _viewType),
      ),
    );
  }
}
