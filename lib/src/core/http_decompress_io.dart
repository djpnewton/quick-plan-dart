import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

String decodeResponse(http.Response resp) {
  final enc = resp.headers['content-encoding']?.toLowerCase() ?? '';
  final bytes = resp.bodyBytes;
  try {
    if (enc.contains('gzip')) return utf8.decode(gzip.decode(bytes));
    if (enc.contains('deflate')) return utf8.decode(zlib.decode(bytes));
  } catch (_) {
    // Fall back to raw body on decompression failure.
  }
  return resp.body;
}
