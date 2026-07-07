import 'dart:io';

import 'package:flutter/services.dart';

class ForumCookieBridge {
  const ForumCookieBridge();

  static const MethodChannel _channel = MethodChannel('forumhub/session');

  Future<String?> cookieHeaderFor(Uri uri) async {
    if (!Platform.isIOS) {
      return null;
    }

    try {
      final String? header = await _channel.invokeMethod<String>(
        'getCookieHeader',
        <String, String>{
          'url': uri.toString(),
        },
      );
      if (header == null || header.trim().isEmpty) {
        return null;
      }
      return header;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
