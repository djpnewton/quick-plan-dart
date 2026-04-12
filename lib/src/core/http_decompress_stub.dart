import 'package:http/http.dart' as http;

// On web the browser already decompresses responses — just return the body.
String decodeResponse(http.Response resp) => resp.body;
