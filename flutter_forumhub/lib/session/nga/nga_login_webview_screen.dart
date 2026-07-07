import 'package:flutter/material.dart';
import 'package:flutter_forumhub/app/theme/app_theme.dart';
import 'package:flutter_forumhub/session/nga/nga_session_controller.dart';
import 'package:flutter_forumhub/session/nga/nga_login_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

class NgaLoginWebViewScreen extends ConsumerStatefulWidget {
  const NgaLoginWebViewScreen({super.key});

  @override
  ConsumerState<NgaLoginWebViewScreen> createState() => _NgaLoginWebViewScreenState();
}

class _NgaLoginWebViewScreenState extends ConsumerState<NgaLoginWebViewScreen> {
  late final WebViewController _controller;
  bool _isSyncing = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            if (!mounted) {
              return;
            }
            setState(() {
              _message = _helpMessageFor(url);
            });
          },
          onWebResourceError: (WebResourceError error) {
            if (!mounted) {
              return;
            }
            setState(() {
              _message = '网页加载异常：${error.description}';
            });
          },
        ),
      )
      ..loadRequest(
        Uri.parse('https://bbs.nga.cn/nuke.php?__lib=login&__act=account&login'),
      );
  }

  Future<void> _completeLogin() async {
    setState(() {
      _isSyncing = true;
      _message = '正在同步 NGA 登录 cookies...';
    });

    try {
      final NgaSessionController controller = ref.read(ngaSessionControllerProvider.notifier);
      await controller.syncFromWebLogin();
      final NgaLoginState state = await ref.read(ngaSessionControllerProvider.future);

      if (!mounted) {
        return;
      }

      if (state.isLoggedIn) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _message = '还没有识别到有效登录态。请确认网页已经登录成功，再点完成。';
        });
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _message = '同步失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  String _helpMessageFor(String url) {
    if (url.contains('login')) {
      return '登录完成后点击右上角“完成”，再把 NGA cookies 同步到 Flutter HTTP 请求层。';
    }
    if (url.contains('bbs.nga.cn')) {
      return '如果当前页面已经是登录后的 NGA 页面，可以直接点击右上角“完成”。';
    }
    return '如果网页已经显示登录成功，可以直接点击右上角“完成”。';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录 NGA'),
        actions: <Widget>[
          IconButton(
            onPressed: _isSyncing
                ? null
                : () {
                    _controller.reload();
                  },
            icon: const Icon(Icons.refresh),
          ),
          TextButton(
            onPressed: _isSyncing ? null : _completeLogin,
            child: Text(
              _isSyncing ? '同步中...' : '完成',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (_message != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: AppTheme.paperDeep.withValues(alpha: 0.5),
              child: Text(
                _message!,
                style: const TextStyle(
                  color: AppTheme.secondaryInk,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
          Expanded(
            child: WebViewWidget(controller: _controller),
          ),
        ],
      ),
    );
  }
}
