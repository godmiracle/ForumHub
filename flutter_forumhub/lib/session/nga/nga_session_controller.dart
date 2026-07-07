import 'package:flutter_forumhub/session/nga/nga_login_state.dart';
import 'package:flutter_forumhub/session/nga/nga_session_bridge.dart';
import 'package:flutter_forumhub/session/nga/nga_session_epoch.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final Provider<NgaSessionBridge> ngaSessionBridgeProvider = Provider<NgaSessionBridge>((ref) {
  return const NgaSessionBridge();
});

final AutoDisposeAsyncNotifierProvider<NgaSessionController, NgaLoginState>
    ngaSessionControllerProvider =
    AsyncNotifierProvider.autoDispose<NgaSessionController, NgaLoginState>(
  NgaSessionController.new,
);

class NgaSessionController extends AutoDisposeAsyncNotifier<NgaLoginState> {
  late final NgaSessionBridge _bridge;

  @override
  Future<NgaLoginState> build() async {
    _bridge = ref.read(ngaSessionBridgeProvider);
    return _bridge.readLoginState();
  }

  Future<void> refresh() async {
    state = const AsyncLoading<NgaLoginState>().copyWithPrevious(state);
    state = await AsyncValue.guard(_bridge.refreshLoginState);
  }

  Future<void> syncFromWebLogin() async {
    state = const AsyncLoading<NgaLoginState>().copyWithPrevious(state);
    state = await AsyncValue.guard(() async {
      final NgaLoginState nextState = await _bridge.syncLoginCookies();
      _bumpEpoch();
      return nextState;
    });
  }

  Future<void> logout() async {
    state = const AsyncLoading<NgaLoginState>().copyWithPrevious(state);
    state = await AsyncValue.guard(() async {
      await _bridge.logout();
      _bumpEpoch();
      return NgaLoginState.empty;
    });
  }

  void _bumpEpoch() {
    ref.read(ngaSessionEpochProvider.notifier).state++;
  }
}
