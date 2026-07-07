import 'package:flutter/material.dart';
import 'package:flutter_forumhub/shared/widgets/placeholder_screen.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'History',
      description: '后续迁移本地浏览历史与跨 source 的 thread reopening。',
      icon: Icons.schedule,
    );
  }
}
