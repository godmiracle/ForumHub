import 'package:flutter/material.dart';
import 'package:flutter_forumhub/app/theme/app_theme.dart';
import 'package:flutter_forumhub/domain/models/forum_thread.dart';

class ThreadCard extends StatelessWidget {
  const ThreadCard({
    required this.thread,
    super.key,
  });

  final ForumThread thread;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.paperDeep,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    thread.author.isEmpty ? '?' : thread.author.substring(0, 1),
                    style: const TextStyle(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    thread.author,
                    style: const TextStyle(
                      color: AppTheme.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  thread.createdAt,
                  style: const TextStyle(
                    color: AppTheme.secondaryInk,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                if (thread.isPinned) _MetaChip(label: '置顶'),
                _MetaChip(label: '${thread.replyCount} 回'),
                _MetaChip(label: '${thread.viewCount} 浏览'),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              thread.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (thread.summary.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                thread.summary,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.paperDeep.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.secondaryInk,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
