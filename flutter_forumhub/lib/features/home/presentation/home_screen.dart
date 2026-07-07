import 'package:flutter/material.dart';
import 'package:flutter_forumhub/app/theme/app_theme.dart';
import 'package:flutter_forumhub/domain/models/forum_channel.dart';
import 'package:flutter_forumhub/domain/models/forum_source.dart';
import 'package:flutter_forumhub/features/home/application/home_feed_controller.dart';
import 'package:flutter_forumhub/shared/widgets/thread_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HomeFeedState state = ref.watch(homeFeedControllerProvider);
    final HomeFeedController controller = ref.read(homeFeedControllerProvider.notifier);

    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  state.selectedSource.displayName,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  state.selectedSource == ForumSource.nga
                      ? 'NGA 已开始走真实接口读取；V2EX 和 LINUX DO 目前仍先保留 mock 数据。'
                      : '当前 source 仍先保留 mock 数据，等 NGA 读通后再继续迁移其它 adapter。',
                  style: TextStyle(
                    color: AppTheme.secondaryInk,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: state.availableSources.map((ForumSource source) {
                    final bool isSelected = source == state.selectedSource;
                    return ChoiceChip(
                      label: Text(source.displayName),
                      selected: isSelected,
                      onSelected: (_) {
                        controller.selectSource(source);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemBuilder: (context, index) {
                      final ForumChannel channel = state.channels[index];
                      final bool isActive = channel.id == state.activeChannel?.id;
                      return FilterChip(
                        label: Text(channel.title),
                        selected: isActive,
                        onSelected: (_) {
                          controller.selectChannel(channel);
                        },
                      );
                    },
                    separatorBuilder: (BuildContext context, int index) {
                      return const SizedBox(width: 10);
                    },
                    itemCount: state.channels.length,
                  ),
                ),
                const SizedBox(height: 20),
                if (state.isLoading)
                  const LinearProgressIndicator(minHeight: 2),
                if (state.isLoading) const SizedBox(height: 20),
                if (state.errorMessage != null) ...<Widget>[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            '加载失败',
                            style: TextStyle(
                              color: AppTheme.ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            state.errorMessage!,
                            style: const TextStyle(
                              color: AppTheme.secondaryInk,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonal(
                            onPressed: controller.reload,
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          sliver: state.isLoading
              ? const SliverToBoxAdapter(child: SizedBox.shrink())
              : state.errorMessage != null
                  ? const SliverToBoxAdapter(child: SizedBox.shrink())
                  : state.threads.isEmpty
                  ? const SliverToBoxAdapter(
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Text(
                            '当前 source / channel 下暂时没有帖子。',
                            style: TextStyle(
                              color: AppTheme.secondaryInk,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),
                    )
                  : SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (BuildContext context, int index) {
                          final int threadIndex = index ~/ 2;
                          if (index.isOdd) {
                            return const SizedBox(height: 14);
                          }

                          final thread = state.threads[threadIndex];
                          return InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () {
                              context.goNamed(
                                'thread-detail',
                                pathParameters: <String, String>{
                                  'source': thread.source.name,
                                  'threadId': thread.id,
                                },
                              );
                            },
                            child: ThreadCard(thread: thread),
                          );
                        },
                        childCount: (state.threads.length * 2) - 1,
                      ),
                    ),
        ),
      ],
    );
  }
}
