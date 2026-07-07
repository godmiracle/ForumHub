import 'package:flutter/material.dart';
import 'package:flutter_forumhub/app/router/app_router.dart';
import 'package:flutter_forumhub/core/constants/app_copy.dart';
import 'package:flutter_forumhub/features/community/presentation/community_screen.dart';
import 'package:flutter_forumhub/features/history/presentation/history_screen.dart';
import 'package:flutter_forumhub/features/home/presentation/home_screen.dart';
import 'package:flutter_forumhub/features/user/presentation/user_screen.dart';
import 'package:flutter_forumhub/shared/widgets/glass_tab_bar.dart';
import 'package:go_router/go_router.dart';

class AppShellScreen extends StatelessWidget {
  const AppShellScreen({
    required this.initialTab,
    super.key,
  });

  final AppShellRoute initialTab;

  @override
  Widget build(BuildContext context) {
    final int currentIndex = AppShellRoute.values.indexOf(initialTab);

    final List<Widget> pages = <Widget>[
      const HomeScreen(),
      const CommunityScreen(),
      const HistoryScreen(),
      const UserScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(AppCopy.appName),
            Text(
              AppCopy.phaseLabel,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: currentIndex,
        children: pages,
      ),
      bottomNavigationBar: GlassTabBar(
        currentIndex: currentIndex,
        onSelected: (int index) {
          final AppShellRoute route = AppShellRoute.values[index];
          if (route != initialTab) {
            context.goNamed(route.name);
          }
        },
        destinations: const <GlassTabDestination>[
          GlassTabDestination(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home_rounded,
            label: 'Home',
          ),
          GlassTabDestination(
            icon: Icons.grid_view_rounded,
            selectedIcon: Icons.grid_view,
            label: 'Community',
          ),
          GlassTabDestination(
            icon: Icons.history_rounded,
            selectedIcon: Icons.history,
            label: 'History',
          ),
          GlassTabDestination(
            icon: Icons.person_outline_rounded,
            selectedIcon: Icons.person,
            label: 'User',
          ),
        ],
      ),
    );
  }
}
