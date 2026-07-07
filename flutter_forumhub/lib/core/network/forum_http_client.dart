import 'dart:convert';
import 'dart:io';

import 'package:flutter_forumhub/core/session/forum_cookie_bridge.dart';

class ForumHttpClient {
  ForumHttpClient({
    ForumCookieBridge? cookieBridge,
    HttpClient Function()? clientFactory,
  }) : _cookieBridge = cookieBridge ?? const ForumCookieBridge(),
       _clientFactory = clientFactory ?? HttpClient.new;

  static const String _userAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 ForumHubFlutter/0.1';

  final ForumCookieBridge _cookieBridge;
  final HttpClient Function() _clientFactory;

  Future<String> postForm(
    Uri uri,
    Map<String, String> form,
  ) async {
    final HttpClient client = _clientFactory();
    try {
      final HttpClientRequest request = await client.postUrl(uri);
      final String body = _encodeForm(form);
      final String? cookieHeader = await _cookieBridge.cookieHeaderFor(uri);

      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/x-www-form-urlencoded; charset=utf-8',
      );
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      if (cookieHeader != null) {
        request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      }

      request.add(utf8.encode(body));

      final HttpClientResponse response = await request.close();
      final List<int> bytes = await response.fold<List<int>>(
        <int>[],
        (List<int> collected, List<int> chunk) {
          return <int>[...collected, ...chunk];
        },
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'ForumHub HTTP ${response.statusCode} for $uri',
          uri: uri,
        );
      }

      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      client.close(force: true);
    }
  }

  String _encodeForm(Map<String, String> form) {
    return form.entries
        .map((MapEntry<String, String> entry) {
          return '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}';
        })
        .join('&');
  }
}
