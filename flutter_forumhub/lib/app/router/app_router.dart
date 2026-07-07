import 'package:flutter/cupertino.dart';
import 'package:flutter_forumhub/domain/models/forum_source.dart';
import 'package:flutter_forumhub/features/shell/presentation/app_shell_screen.dart';
import 'package:flutter_forumhub/features/thread_detail/application/thread_detail_controller.dart';
import 'package:flutter_forumhub/features/thread_detail/presentation/thread_detail_screen.dart';
import 'package:go_router/go_router.dart';

final class AppRouter {
  static final GoRouter config = GoRouter(
    initialLocation: AppShellRoute.home.path,
    routes: <RouteBase>[
      GoRoute(
        path: AppShellRoute.home.path,
        name: AppShellRoute.home.name,
        builder: (context, state) => const AppShellScreen(initialTab: AppShellRoute.home),
      ),
      GoRoute(
        path: AppShellRoute.community.path,
        name: AppShellRoute.community.name,
        builder: (context, state) => const AppShellScreen(initialTab: AppShellRoute.community),
      ),
      GoRoute(
        path: AppShellRoute.history.path,
        name: AppShellRoute.history.name,
        builder: (context, state) => const AppShellScreen(initialTab: AppShellRoute.history),
      ),
      GoRoute(
        path: AppShellRoute.user.path,
        name: AppShellRoute.user.name,
        builder: (context, state) => const AppShellScreen(initialTab: AppShellRoute.user),
      ),
      GoRoute(
        path: '/thread/:source/:threadId',
        name: 'thread-detail',
        pageBuilder: (context, state) {
          final String sourceValue = state.pathParameters['source'] ?? ForumSource.nga.name;
          final String threadId = state.pathParameters['threadId'] ?? '';
          final ForumSource source = ForumSource.values.firstWhere(
            (ForumSource item) => item.name == sourceValue,
            orElse: () => ForumSource.nga,
          );

          return CupertinoPage<void>(
            key: state.pageKey,
            child: ThreadDetailScreen(
              args: ThreadDetailArgs(
                source: source,
                threadId: threadId,
              ),
            ),
          );
        },
      ),
    ],
  );
}

enum AppShellRoute {
  home(name: 'home', path: '/'),
  community(name: 'community', path: '/community'),
  history(name: 'history', path: '/history'),
  user(name: 'user', path: '/user');

  const AppShellRoute({
    required this.name,
    required this.path,
  });

  final String name;
  final String path;
}
