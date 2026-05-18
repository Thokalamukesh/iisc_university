// ignore_for_file: avoid_web_libraries_in_flutter, undefined_prefixed_name

import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:api_selfxo_project/core/local_image_asset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
  final List<String> fallbackUrls;
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
    this.fallbackUrls = const [],
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
  int _activeUrlIndex = 0;
  List<String> get _candidateUrls {
    final seen = <String>{};
    return <String>[widget.url, ...widget.fallbackUrls]
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty && seen.add(url))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _viewType = 'app-network-image-${_nextNetworkImageId++}';
    _imageElement = html.ImageElement();
    _bindEvents();
    _updateImageElement();
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _imageElement,
    );
  }

  @override
  void didUpdateWidget(covariant AppNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.fallbackUrls.join('|') != widget.fallbackUrls.join('|') ||
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
      if (_tryNextUrl()) return;
      setState(() => _hasError = true);
    });
  }

  void _updateImageElement() {
    if (_disposed) return;

    _activeUrlIndex = 0;
    final candidates = _candidateUrls;
    final trimmedUrl = candidates.isEmpty ? '' : candidates.first;
    _hasError = trimmedUrl.isEmpty;

    if (trimmedUrl.isEmpty || localImageAssetForUrl(trimmedUrl) != null) {
      _imageElement.src = '';
      return;
    }

    _imageElement
      ..src = trimmedUrl
      ..alt = ''
      ..draggable = false
      // Let the browser lazily decode off-screen menu images. This reduces
      // route-change jank when a category list has many product photos.
      ..setAttribute('loading', 'lazy')
      ..setAttribute('decoding', 'async')
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

  bool _tryNextUrl() {
    final candidates = _candidateUrls;
    if (_activeUrlIndex >= candidates.length - 1) return false;
    _activeUrlIndex++;
    _imageElement.src = candidates[_activeUrlIndex];
    return true;
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
    final candidates = _candidateUrls;
    final trimmedUrl = candidates.isEmpty ? '' : candidates.first;
    if (trimmedUrl.isEmpty) return widget.fallback;

    final localAsset = localImageAssetForUrl(trimmedUrl);
    if (localAsset != null) {
      if (localAsset.isSvg) {
        return SvgPicture.asset(
          localAsset.path,
          fit: widget.fit,
          alignment: widget.alignment,
          width: widget.width,
          height: widget.height,
          placeholderBuilder: (_) => widget.fallback,
        );
      }

      return Image.asset(
        localAsset.path,
        fit: widget.fit,
        alignment: widget.alignment,
        width: widget.width,
        height: widget.height,
        cacheWidth: widget.cacheWidth,
        cacheHeight: widget.cacheHeight,
        gaplessPlayback: widget.gaplessPlayback,
        errorBuilder: (_, __, ___) => widget.fallback,
      );
    }

    if (_hasError) return widget.fallback;

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
