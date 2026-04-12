import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'garmin_models.dart';
import 'http_decompress.dart';

/// Handles authentication against Garmin Connect via the mobile JSON API +
/// OAuth1→OAuth2 exchange flow. Uses browser-like headers on SSO endpoints
/// to pass Cloudflare's bot checks.
class GarminAuth {
  GarminAuth(this.email, this.password, this.client, {this.onLog});

  final String email;
  final String password;
  final http.Client client;
  final void Function(String)? onLog;

  GarminSession? _cached;

  static const _ssoBase = 'https://sso.garmin.com';
  static const _oauthApiBase =
      'https://connectapi.garmin.com/oauth-service/oauth';

  // iOS client ID/service — matches actual Garmin Connect iOS app flow.
  static const _clientId = 'GCM_IOS_DARK';
  static const _serviceUrl = 'https://mobile.integration.garmin.com/gcm/ios';

  // iOS app user agent for OAuth steps (connectapi.garmin.com is unaffected
  // by Cloudflare, but headers must match the client ID being used).
  static const _iosAppVersion = '5.23.1';
  static const _iosOAuthUA = 'GCM-iOS-$_iosAppVersion.1';
  static const _iosGarminUA =
      'com.garmin.connect.mobile/$_iosAppVersion.1;;'
      'Apple/iPhone14,7/;iOS/26.3.1;CFNetwork/1.0(Darwin/25.3.0)';

  // Browser headers for the SSO page GET (navigation request).
  static const _ssoNavUA =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148';
  static const Map<String, String> _ssoNavHeaders = {
    'User-Agent': _ssoNavUA,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
    'Accept-Encoding': 'gzip, deflate',
    'Connection': 'keep-alive',
    'Sec-Fetch-Mode': 'navigate',
    'Sec-Fetch-Site': 'none',
    'Sec-Fetch-Dest': 'document',
    'Sec-Fetch-User': '?1',
  };

  // Headers for the JSON credential POST (JS fetch/XHR from the SPA).
  static const Map<String, String> _ssoFetchHeaders = {
    'User-Agent': _ssoNavUA,
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'en-US,en;q=0.9',
    'Accept-Encoding': 'gzip, deflate',
    'Connection': 'keep-alive',
    'Sec-Fetch-Mode': 'cors',
    'Sec-Fetch-Site': 'same-origin',
    'Sec-Fetch-Dest': 'empty',
    'Origin': _ssoBase,
  };

  // iOS app headers for connectapi.garmin.com OAuth steps.
  static const Map<String, String> _iosOAuthHeaders = {
    'User-Agent': _iosOAuthUA,
    'X-app-ver': _iosAppVersion,
    'X-Garmin-User-Agent': _iosGarminUA,
  };

  /// Returns a valid [GarminSession], logging in if necessary.
  ///
  /// Set [forceNew] to discard any cached session and re-authenticate.
  Future<GarminSession> login({bool forceNew = false}) async {
    if (!forceNew && _cached != null) return _cached!;
    _cached = await _performLogin();
    return _cached!;
  }

  // ---------------------------------------------------------------------------
  // Login flow
  // ---------------------------------------------------------------------------

  Future<GarminSession> _performLogin() async {
    final loginQS = _buildQS({
      'clientId': _clientId,
      'locale': 'en-US',
      'service': _serviceUrl,
    });

    // Step 1: GET /mobile/sso/en/sign-in — sets Cloudflare / session cookies.
    onLog?.call('  [1/6] Fetching SSO sign-in page…');
    var jar = <String, String>{};
    {
      final resp = await client.get(
        Uri.parse('$_ssoBase/mobile/sso/en/sign-in?clientId=$_clientId'),
        headers: _ssoNavHeaders,
      );
      jar = _mergeCookies(jar, resp);
    }

    // Simulate human time to fill in the login form (2–5 s random delay).
    // Cloudflare WAF rate-limits bots that submit credentials immediately.
    onLog?.call('  [2/6] Waiting before submitting credentials…');
    await Future.delayed(Duration(milliseconds: 2000 + Random().nextInt(3000)));

    // Step 2: POST /mobile/api/login — JSON credentials, returns service ticket.
    onLog?.call('  [3/6] Submitting credentials…');
    String ticket;
    {
      final resp = await client.post(
        Uri.parse('$_ssoBase/mobile/api/login?$loginQS'),
        headers: {
          ..._ssoFetchHeaders,
          'Content-Type': 'application/json',
          'Referer': '$_ssoBase/mobile/sso/en/sign-in?clientId=$_clientId',
          'Cookie': _cookieHeader(jar),
        },
        body: jsonEncode({
          'username': email,
          'password': password,
          'rememberMe': false,
          'captchaToken': '',
        }),
      );
      jar = _mergeCookies(jar, resp);

      if (resp.statusCode == 429) {
        throw Exception(
          'Rate limited by Garmin SSO (429). '
          'Wait a few minutes and try again.',
        );
      }

      final Map<String, dynamic> body;
      try {
        body = jsonDecode(decodeResponse(resp)) as Map<String, dynamic>;
      } catch (_) {
        final raw = decodeResponse(resp);
        throw Exception(
          'Unexpected non-JSON response from Garmin SSO '
          '(status ${resp.statusCode}). Body: ${raw.substring(0, min(400, raw.length))}',
        );
      }

      final status = body['responseStatus'] as Map<String, dynamic>?;
      final type = status?['type'] as String?;

      if (type == 'MFA_REQUIRED') {
        throw Exception(
          'Two-factor authentication is required. '
          'Disable 2FA on your Garmin account to use this app.',
        );
      }

      if (type != 'SUCCESSFUL') {
        final msg = status?['message'] as String? ?? type ?? 'unknown';
        throw Exception('Login failed: $msg. Check your email/password.');
      }

      final t = body['serviceTicketId'] as String?;
      if (t == null || t.isEmpty) {
        throw Exception(
          'No service ticket in SSO response. Body: ${decodeResponse(resp)}',
        );
      }
      ticket = t;
    }

    // Step 3 (best-effort): GET /portal/sso/embed — Cloudflare LB pinning.
    onLog?.call('  [4/6] Fetching OAuth consumer credentials…');
    try {
      final resp = await client.get(
        Uri.parse('$_ssoBase/portal/sso/embed'),
        headers: {
          ..._ssoNavHeaders,
          'Sec-Fetch-Site': 'same-origin',
          'Cookie': _cookieHeader(jar),
        },
      );
      jar = _mergeCookies(jar, resp);
    } catch (_) {
      // Best-effort — ignore failures.
    }

    // Step 4: Fetch OAuth1 consumer key/secret from garth's S3 bucket.
    final String consumerKey;
    final String consumerSecret;
    {
      final resp = await client.get(
        Uri.parse('https://thegarth.s3.amazonaws.com/oauth_consumer.json'),
      );
      final body = jsonDecode(decodeResponse(resp)) as Map<String, dynamic>;
      consumerKey = body['consumer_key'] as String;
      consumerSecret = body['consumer_secret'] as String;
    }

    // Step 5: OAuth1-signed GET /preauthorized — exchange ticket for OAuth1 token.
    onLog?.call('  [5/6] Exchanging service ticket for OAuth1 token…');
    final String oauth1Token;
    final String oauth1Secret;
    {
      const preauthorizedUrl = '$_oauthApiBase/preauthorized';
      final queryParams = {
        'ticket': ticket,
        'login-url': _serviceUrl,
        'accepts-mfa-tokens': 'true',
      };
      final authHeader = _oauth1Header(
        method: 'GET',
        url: preauthorizedUrl,
        consumerKey: consumerKey,
        consumerSecret: consumerSecret,
        tokenKey: '',
        tokenSecret: '',
        extraParams: queryParams,
      );
      final uri = Uri.parse(
        preauthorizedUrl,
      ).replace(queryParameters: queryParams);
      final resp = await client.get(
        uri,
        headers: {..._iosOAuthHeaders, 'Authorization': authHeader},
      );
      final params = Map.fromEntries(
        decodeResponse(resp).split('&').map((pair) {
          final kv = pair.split('=');
          return MapEntry(
            kv[0],
            Uri.decodeComponent(kv.length > 1 ? kv[1] : ''),
          );
        }),
      );
      final tok = params['oauth_token'];
      final sec = params['oauth_token_secret'];
      if (tok == null || sec == null) {
        throw Exception(
          'Cannot parse OAuth1 token response. Body: ${decodeResponse(resp)}',
        );
      }
      oauth1Token = tok;
      oauth1Secret = sec;
    }

    // Step 6: OAuth1-signed POST /exchange/user/2.0 — get OAuth2 Bearer token.
    // The form body param `audience` is included in the OAuth1 signature base
    // string per RFC 5849 §3.4.1.3.
    onLog?.call('  [6/6] Exchanging OAuth1 token for Bearer token…');
    {
      const exchangeUrl = '$_oauthApiBase/exchange/user/2.0';
      const exchangeBody = {'audience': 'GARMIN_CONNECT_MOBILE_IOS_DI'};
      final authHeader = _oauth1Header(
        method: 'POST',
        url: exchangeUrl,
        consumerKey: consumerKey,
        consumerSecret: consumerSecret,
        tokenKey: oauth1Token,
        tokenSecret: oauth1Secret,
        extraParams: exchangeBody,
      );
      final resp = await client.post(
        Uri.parse(exchangeUrl),
        headers: {
          ..._iosOAuthHeaders,
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': authHeader,
        },
        body: _buildQS(exchangeBody),
      );
      final body = jsonDecode(decodeResponse(resp)) as Map<String, dynamic>;
      final accessToken = body['access_token'] as String?;
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception(
          'Cannot parse OAuth2 token response. Body: ${decodeResponse(resp)}',
        );
      }
      return GarminSession(accessToken);
    }
  }

  // ---------------------------------------------------------------------------
  // OAuth1 HMAC-SHA1 header building
  // ---------------------------------------------------------------------------

  String _oauth1Header({
    required String method,
    required String url,
    required String consumerKey,
    required String consumerSecret,
    required String tokenKey,
    required String tokenSecret,
    required Map<String, String> extraParams,
  }) {
    final nonce = const Uuid().v4().replaceAll('-', '');
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000)
        .toString();

    final oauthParams = <String, String>{
      'oauth_consumer_key': consumerKey,
      'oauth_nonce': nonce,
      'oauth_signature_method': 'HMAC-SHA1',
      'oauth_timestamp': timestamp,
      'oauth_version': '1.0',
      if (tokenKey.isNotEmpty) 'oauth_token': tokenKey,
    };

    final allParams = {...oauthParams, ...extraParams};
    final paramString =
        (allParams.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
            .map((e) => '${_pct(e.key)}=${_pct(e.value)}')
            .join('&');

    final base = '${method.toUpperCase()}&${_pct(url)}&${_pct(paramString)}';
    final signingKey = '${_pct(consumerSecret)}&${_pct(tokenSecret)}';

    final hmac = Hmac(sha1, utf8.encode(signingKey));
    final sig = base64.encode(hmac.convert(utf8.encode(base)).bytes);

    final headerParams = {...oauthParams, 'oauth_signature': sig};
    final headerStr =
        (headerParams.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
            .map((e) => '${e.key}="${_pct(e.value)}"')
            .join(', ');

    return 'OAuth $headerStr';
  }

  // ---------------------------------------------------------------------------
  // HTTP helpers
  // ---------------------------------------------------------------------------

  static String _pct(String s) => Uri.encodeComponent(
    s,
  ).replaceAll('+', '%20').replaceAll('*', '%2A').replaceAll('%7E', '~');

  static String _buildQS(Map<String, String> params) => params.entries
      .map(
        (e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
      )
      .join('&');

  static Map<String, String> _mergeCookies(
    Map<String, String> jar,
    http.Response resp,
  ) {
    final updated = Map<String, String>.from(jar);
    for (final header in resp.headers.entries.where(
      (e) => e.key.toLowerCase() == 'set-cookie',
    )) {
      for (final cookie in header.value.split(',')) {
        final nameValue = cookie.trim().split(';').first;
        final eqIdx = nameValue.indexOf('=');
        if (eqIdx > 0) {
          updated[nameValue.substring(0, eqIdx).trim()] = nameValue
              .substring(eqIdx + 1)
              .trim();
        }
      }
    }
    return updated;
  }

  static String _cookieHeader(Map<String, String> jar) =>
      jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
}
