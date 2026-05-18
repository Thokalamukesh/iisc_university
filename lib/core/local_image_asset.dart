class LocalImageAsset {
  final String path;
  final bool isSvg;

  const LocalImageAsset({
    required this.path,
    required this.isSvg,
  });
}

const LocalImageAsset foodSvgAsset = LocalImageAsset(
  path: 'assets/images/food.svg',
  isSvg: true,
);

LocalImageAsset? localImageAssetForUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.hasScheme) {
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();

    if (host == 'gitam.sirixo.com' && path == '/img/food.svg') {
      return foodSvgAsset;
    }
  }

  final normalized =
      trimmed.split('?').first.replaceAll('\\', '/').toLowerCase();
  if (normalized.endsWith('/img/food.svg') || normalized == 'food.svg') {
    return foodSvgAsset;
  }

  return null;
}
