import 'package:flutter/services.dart';
import 'package:flutter_forumhub/session/nga/nga_login_state.dart';

class NgaSessionBridge {
  const NgaSessionBridge();

  static const MethodChannel _channel = MethodChannel('forumhub/session');

  Future<NgaLoginState> readLoginState() async {
    final Map<Object?, Object?>? result = await _channel.invokeMapMethod<Object?, Object?>(
      'readNgaLoginState',
    );
    if (result == null) {
      return NgaLoginState.empty;
    }
    return NgaLoginState.fromMap(result);
  }

  Future<NgaLoginState> refreshLoginState() async {
    final Map<Object?, Object?>? result = await _channel.invokeMapMethod<Object?, Object?>(
      'refreshNgaLoginState',
    );
    if (result == null) {
      return NgaLoginState.empty;
    }
    return NgaLoginState.fromMap(result);
  }

  Future<NgaLoginState> syncLoginCookies() async {
    final Map<Object?, Object?>? result = await _channel.invokeMapMethod<Object?, Object?>(
      'syncNgaLoginCookies',
    );
    if (result == null) {
      return NgaLoginState.empty;
    }
    return NgaLoginState.fromMap(result);
  }

  Future<void> logout() {
    return _channel.invokeMethod<void>('clearNgaLoginCookies');
  }
}
