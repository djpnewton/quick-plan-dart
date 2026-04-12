import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'garmin_models.dart';

/// Handles authentication against Garmin Connect via a 6-step OAuth1→OAuth2
/// flow. Caches the resulting [GarminSession] for the lifetime of this object.
class GarminAuth {
  GarminAuth(this.email, this.password, this.client);

  final String email;
  final String password;
  final http.Client client;

  GarminSession? _cached;

  static const _ssoBase = 'https://sso.garmin.com/sso';
  static const _ssoEmbed = '$_ssoBase/embed';
  static const _oauthApiBase =
      'https://connectapi.garmin.com/oauth-service/oauth';
  static const _ssoUA = 'GCM-iOS-5.7.2.1';
  static const _androidUA = 'com.garmin.android.apps.connectmobile';

  /// Returns a valid [GarminSession], logging in if necessary.
  ///
  /// Set [forceNew] to discard any cached session and re-authenticate.
  Future<GarminSession> login({bool forceNew = false}) async {
    if (!forceNew && _cached != null) return _cached!;
    _cached = await _performLogin();
    return _cached!;
  }

  // ---------------------------------------------------------------------------
  // 6-step login flow
  // ---------------------------------------------------------------------------

  Future<GarminSession> _performLogin() async {
    final csrfRx = RegExp(r'name="_csrf"\s+value="(.+?)"');
    final ticketRx = RegExp(r'embed\?ticket=([^"]+)');
    final titleRx = RegExp(r'<title>(.+?)</title>');

    final embedParams = _buildQS({
      'id': 'gauth-widget',
      'embedWidget': 'true',
      'gauthHost': _ssoBase,
    });
    final signinParams = _buildQS({
      'id': 'gauth-widget',
      'embedWidget': 'true',
      'gauthHost': _ssoEmbed,
      'service': _ssoEmbed,
      'source': _ssoEmbed,
      'redirectAfterAccountLoginUrl': _ssoEmbed,
      'redirectAfterAccountCreationUrl': _ssoEmbed,
    });

    // Step 1: GET /sso/embed – capture initial cookies
    var jar = <String, String>{};
    {
      final resp = await client.get(
        Uri.parse('$_ssoEmbed?$embedParams'),
        headers: {'User-Agent': _ssoUA},
      );
      jar = _mergeCookies(jar, resp);
    }

    // Step 2: GET /sso/signin – extract CSRF token
    String csrf;
    {
      final signinUrl = '$_ssoBase/signin?$signinParams';
      final resp = await client.get(
        Uri.parse(signinUrl),
        headers: {
          'User-Agent': _ssoUA,
          'Cookie': _cookieHeader(jar),
          'Referer': '$_ssoEmbed?$embedParams',
        },
      );
      jar = _mergeCookies(jar, resp);
      final m = csrfRx.firstMatch(resp.body);
      if (m == null) {
        throw Exception(
          'Cannot find CSRF token in SSO signin page. '
          'Check account or try again later. HTML: ${resp.body.substring(0, 400)}',
        );
      }
      csrf = m.group(1)!;
    }

    // Step 3: POST /sso/signin – submit credentials, extract ticket
    String ticket;
    {
      final signinUrl = '$_ssoBase/signin?$signinParams';
      final formBody = _buildQS({
        'username': email,
        'password': password,
        'embed': 'true',
        '_csrf': csrf,
      });
      final resp = await client.post(
        Uri.parse(signinUrl),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': _ssoUA,
          'Cookie': _cookieHeader(jar),
          'Referer': signinUrl,
        },
        body: formBody,
      );
      if (resp.statusCode == 429) {
        throw Exception(
          'Rate limited by Garmin SSO (429). Please wait a few minutes and try again.',
        );
      }
      if (resp.body.contains('ACCOUNT_LOCKED')) {
        throw Exception(
          'Garmin account is locked. Too many failed login attempts. '
          'Unlock it at connect.garmin.com and try again.',
        );
      }
      final tm = ticketRx.firstMatch(resp.body);
      if (tm == null) {
        final title = titleRx.firstMatch(resp.body)?.group(1) ?? 'unknown';
        if (title.contains('MFA')) {
          throw Exception(
            'MFA is required but not supported. Disable 2FA on your Garmin account.',
          );
        }
        throw Exception(
          'Login failed. Check your email/password. (page title: $title)',
        );
      }
      ticket = tm.group(1)!;
    }

    // Step 4: Fetch OAuth1 consumer credentials from garth's S3 bucket
    final String consumerKey;
    final String consumerSecret;
    {
      final resp = await client.get(
        Uri.parse('https://thegarth.s3.amazonaws.com/oauth_consumer.json'),
      );
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      consumerKey = body['consumer_key'] as String;
      consumerSecret = body['consumer_secret'] as String;
    }

    // Step 5: OAuth1-signed GET → exchange ticket for OAuth1 token
    final String oauth1Token;
    final String oauth1Secret;
    {
      final preauthorizedUrl = '$_oauthApiBase/preauthorized';
      final queryParams = {
        'ticket': ticket,
        'login-url': _ssoEmbed,
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
        headers: {'Authorization': authHeader, 'User-Agent': _androidUA},
      );
      final params = Map.fromEntries(
        resp.body.split('&').map((pair) {
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
          'Cannot parse OAuth1 token response. Body: ${resp.body}',
        );
      }
      oauth1Token = tok;
      oauth1Secret = sec;
    }

    // Step 6: OAuth1-signed POST → exchange OAuth1 for OAuth2 Bearer
    {
      final exchangeUrl = '$_oauthApiBase/exchange/user/2.0';
      final authHeader = _oauth1Header(
        method: 'POST',
        url: exchangeUrl,
        consumerKey: consumerKey,
        consumerSecret: consumerSecret,
        tokenKey: oauth1Token,
        tokenSecret: oauth1Secret,
        extraParams: {},
      );
      final resp = await client.post(
        Uri.parse(exchangeUrl),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': authHeader,
          'User-Agent': _androidUA,
        },
      );
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final accessToken = body['access_token'] as String?;
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception(
          'Cannot parse OAuth2 token response. Body: ${resp.body}',
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
