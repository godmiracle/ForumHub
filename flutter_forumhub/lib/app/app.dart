import 'package:flutter/material.dart';
import 'package:flutter_forumhub/app/router/app_router.dart';
import 'package:flutter_forumhub/app/theme/app_theme.dart';

class ForumHubApp extends StatelessWidget {
  const ForumHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'ForumHub',
      theme: AppTheme.light(),
      routerConfig: AppRouter.config,
      debugShowCheckedModeBanner: false,
    );
  }
}
