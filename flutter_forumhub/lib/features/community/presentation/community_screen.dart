import 'package:flutter/material.dart';
import 'package:flutter_forumhub/shared/widgets/placeholder_screen.dart';

class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Community',
      description: '这里会承接栏目订阅、排序和社区管理，不再承担主 source switch 的全部责任。',
      icon: Icons.grid_view_rounded,
    );
  }
}
