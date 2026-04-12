import 'package:flutter/foundation.dart' show kIsWeb;

// _proxyTemplate can be set to get around the garmin CORS policy
const _proxyTemplate = 'https://proxy.corsfix.com/?<REAL_URL>';

/// On web with _proxyTemplate configured, rewrites [url] through the proxy by
/// substituting `<REAL_URL>` with the full target URL.
/// On native, or when _proxyTemplate is not set, returns [url] unchanged.
Uri proxyUri(String url) {
  if (!kIsWeb || _proxyTemplate.isEmpty) return Uri.parse(url);
  return Uri.parse(_proxyTemplate.replaceAll('<REAL_URL>', url));
}
