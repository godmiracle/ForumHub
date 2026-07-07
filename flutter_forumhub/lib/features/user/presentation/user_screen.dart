import 'package:flutter/material.dart';
import 'package:flutter_forumhub/app/theme/app_theme.dart';
import 'package:flutter_forumhub/session/nga/nga_login_state.dart';
import 'package:flutter_forumhub/session/nga/nga_login_webview_screen.dart';
import 'package:flutter_forumhub/session/nga/nga_session_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UserScreen extends ConsumerWidget {
  const UserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<NgaLoginState> ngaSession = ref.watch(ngaSessionControllerProvider);
    final NgaSessionController controller = ref.read(ngaSessionControllerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text(
          '账号与会话',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 28),
        ),
        const SizedBox(height: 8),
        const Text(
          '先打通 NGA Web 登录和 cookie 同步，再继续迁移收藏、回复和跨 source 账号能力。',
          style: TextStyle(
            color: AppTheme.secondaryInk,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ngaSession.when(
              data: (NgaLoginState state) {
                return _NgaSessionCard(
                  state: state,
                  onLogin: () async {
                    final bool? didComplete = await Navigator.of(context).push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (_) => const NgaLoginWebViewScreen(),
                      ),
                    );
                    if (didComplete == true) {
                      await controller.refresh();
                    }
                  },
                  onRefresh: controller.refresh,
                  onLogout: state.isLoggedIn ? controller.logout : null,
                );
              },
              loading: () => const _SessionLoadingCard(),
              error: (Object error, StackTrace stackTrace) {
                return _SessionErrorCard(
                  message: error.toString(),
                  onRetry: controller.refresh,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _NgaSessionCard extends StatelessWidget {
  const _NgaSessionCard({
    required this.state,
    required this.onLogin,
    required this.onRefresh,
    required this.onLogout,
  });

  final NgaLoginState state;
  final Future<void> Function() onRefresh;
  final Future<void> Function()? onLogout;
  final Future<void> Function() onLogin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.paperDeep,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.login_outlined, color: AppTheme.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('NGA', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    state.statusLabel,
                    style: const TextStyle(
                      color: AppTheme.secondaryInk,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          state.isLoggedIn
              ? '已同步 NGA 登录态，当前 CID：${state.cidPreview}'
              : '当前还没有识别到有效 NGA 登录态。你可以先网页登录，再点完成同步。',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 10),
        Text(
          state.cookieNames.isEmpty
              ? 'Cookie: 暂无'
              : 'Cookie: ${state.cookieNames.join(', ')}',
          style: const TextStyle(
            color: AppTheme.secondaryInk,
            fontSize: 12,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '说明：当前账号页会在用户主动刷新或完成网页登录时同步 WebKit cookies，避免在 App 启动阶段访问 WebKit 状态重新引入真机闪退。',
          style: TextStyle(
            color: AppTheme.secondaryInk,
            fontSize: 12,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            FilledButton(
              onPressed: onLogin,
              child: Text(state.isLoggedIn ? '重新登录' : '网页登录'),
            ),
            FilledButton.tonal(
              onPressed: onRefresh,
              child: const Text('刷新状态'),
            ),
            if (onLogout != null)
              OutlinedButton(
                onPressed: onLogout,
                child: const Text('退出登录'),
              ),
          ],
        ),
      ],
    );
  }
}

class _SessionLoadingCard extends StatelessWidget {
  const _SessionLoadingCard();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        LinearProgressIndicator(minHeight: 2),
        SizedBox(height: 16),
        Text(
          '正在读取 NGA 登录状态...',
          style: TextStyle(
            color: AppTheme.secondaryInk,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

class _SessionErrorCard extends StatelessWidget {
  const _SessionErrorCard({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          '登录状态读取失败',
          style: TextStyle(
            color: AppTheme.ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          message,
          style: const TextStyle(
            color: AppTheme.secondaryInk,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.tonal(
          onPressed: onRetry,
          child: const Text('重试'),
        ),
      ],
    );
  }
}
