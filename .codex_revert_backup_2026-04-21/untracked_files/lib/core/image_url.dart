import 'package:api_selfxo_project/api/dio_client.dart';

String normalizeImageUrl(String? raw) {
  final trimmed = (raw ?? '').trim();
  if (trimmed.isEmpty) return '';

  final normalized = trimmed.replaceAll('\\', '/');

  if (normalized.startsWith('data:')) {
    return normalized;
  }
  if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
    return _encodeWebSafeUrl(normalized);
  }
  if (normalized.startsWith('//')) {
    return _encodeWebSafeUrl('https:$normalized');
  }
  if (RegExp(r'^[A-Za-z0-9.-]+\.[A-Za-z]{2,}(/|$)').hasMatch(normalized)) {
    return _encodeWebSafeUrl('https://$normalized');
  }

  var base = DioClient.baseUrl;
  if (base.contains('/api/')) {
    base = base.replaceFirst('/api/', '/');
  }
  if (!base.endsWith('/')) {
    base = '$base/';
  }

  final path = normalized.startsWith('/')
      ? normalized.substring(1)
      : normalized;
  return _encodeWebSafeUrl('$base$path');
}

String normalizeImageUrlValue(dynamic value) {
  return normalizeImageUrl(value?.toString());
}

String _encodeWebSafeUrl(String url) {
  try {
    return Uri.encodeFull(url);
  } catch (_) {
    return url;
  }
}
