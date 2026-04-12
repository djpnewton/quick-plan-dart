// Conditional export: dart:io decompression on native, passthrough on web.
export 'http_decompress_stub.dart'
    if (dart.library.io) 'http_decompress_io.dart';
