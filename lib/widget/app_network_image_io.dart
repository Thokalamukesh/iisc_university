import 'package:api_selfxo_project/core/local_image_asset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AppNetworkImage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final seen = <String>{};
    final candidates = <String>[url, ...fallbackUrls]
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty && seen.add(url))
        .toList();
    final trimmedUrl = candidates.isEmpty ? '' : candidates.first;
    if (trimmedUrl.isEmpty) return fallback;

    final localAsset = localImageAssetForUrl(trimmedUrl);
    if (localAsset != null) {
      if (localAsset.isSvg) {
        return SvgPicture.asset(
          localAsset.path,
          fit: fit,
          alignment: alignment,
          width: width,
          height: height,
          placeholderBuilder: (_) => fallback,
        );
      }

      return Image.asset(
        localAsset.path,
        fit: fit,
        alignment: alignment,
        width: width,
        height: height,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        gaplessPlayback: gaplessPlayback,
        errorBuilder: (_, __, ___) => fallback,
      );
    }

    final dataUri = _tryParseDataUri(trimmedUrl);
    if (dataUri != null && dataUri.mimeType.startsWith('image/')) {
      if (dataUri.mimeType == 'image/svg+xml') {
        return SvgPicture.string(
          dataUri.contentAsString(),
          fit: fit,
          alignment: alignment,
          width: width,
          height: height,
          placeholderBuilder: (_) => fallback,
        );
      }

      return Image.memory(
        dataUri.contentAsBytes(),
        fit: fit,
        alignment: alignment,
        width: width,
        height: height,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        gaplessPlayback: gaplessPlayback,
        errorBuilder: (_, __, ___) => fallback,
      );
    }

    if (_isSvgUrl(trimmedUrl)) {
      return SvgPicture.network(
        trimmedUrl,
        fit: fit,
        alignment: alignment,
        width: width,
        height: height,
        placeholderBuilder: (_) => fallback,
      );
    }

    final rasterCandidates = candidates
        .where((url) => !_isSvgUrl(url) && _tryParseDataUri(url) == null)
        .toList();
    if (rasterCandidates.isEmpty) return fallback;

    return _NetworkImageWithFallbacks(
      urls: rasterCandidates,
      fit: fit,
      alignment: alignment,
      width: width,
      height: height,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      gaplessPlayback: gaplessPlayback,
      fallback: fallback,
    );
  }
}

UriData? _tryParseDataUri(String url) {
  if (!url.startsWith('data:')) return null;
  try {
    return UriData.parse(url);
  } catch (_) {
    return null;
  }
}

bool _isSvgUrl(String url) {
  final normalized = url.split('?').first.split('#').first.toLowerCase();
  return normalized.endsWith('.svg');
}

class _NetworkImageWithFallbacks extends StatefulWidget {
  final List<String> urls;
  final BoxFit fit;
  final Alignment alignment;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final int? cacheHeight;
  final bool gaplessPlayback;
  final Widget fallback;

  const _NetworkImageWithFallbacks({
    required this.urls,
    required this.fit,
    required this.alignment,
    required this.fallback,
    this.width,
    this.height,
    this.cacheWidth,
    this.cacheHeight,
    this.gaplessPlayback = false,
  });

  @override
  State<_NetworkImageWithFallbacks> createState() =>
      _NetworkImageWithFallbacksState();
}

class _NetworkImageWithFallbacksState
    extends State<_NetworkImageWithFallbacks> {
  int _activeIndex = 0;

  @override
  void didUpdateWidget(covariant _NetworkImageWithFallbacks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urls.join('|') != widget.urls.join('|')) {
      _activeIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) return widget.fallback;
    return Image.network(
      widget.urls[_activeIndex],
      fit: widget.fit,
      alignment: widget.alignment,
      width: widget.width,
      height: widget.height,
      cacheWidth: widget.cacheWidth,
      cacheHeight: widget.cacheHeight,
      gaplessPlayback: widget.gaplessPlayback,
      errorBuilder: (_, __, ___) {
        if (_activeIndex < widget.urls.length - 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _activeIndex++);
          });
          return widget.fallback;
        }
        return widget.fallback;
      },
    );
  }
}
