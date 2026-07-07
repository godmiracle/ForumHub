import 'package:flutter/material.dart';
import 'package:flutter_forumhub/app/theme/app_theme.dart';
import 'package:flutter_forumhub/domain/models/reply.dart';
import 'package:flutter_forumhub/features/thread_detail/application/thread_detail_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ThreadDetailScreen extends ConsumerWidget {
  const ThreadDetailScreen({
    required this.args,
    super.key,
  });

  final ThreadDetailArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThreadDetailState state = ref.watch(threadDetailControllerProvider(args));
    final ThreadDetailController controller =
        ref.read(threadDetailControllerProvider(args).notifier);
    final payload = state.payload;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thread Detail'),
      ),
      body: payload == null && state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : payload == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          state.errorMessage ?? '帖子详情暂时不可用。',
                          style: const TextStyle(color: AppTheme.secondaryInk),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed: () => controller.reload(args),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              : CustomScrollView(
                  slivers: <Widget>[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              payload.thread.title,
                              style:
                                  Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 26),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '${payload.thread.author} · ${payload.thread.createdAt}',
                              style: const TextStyle(
                                color: AppTheme.secondaryInk,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              payload.thread.summary,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: <Widget>[
                                FilterChip(
                                  label: const Text('只看作者'),
                                  selected: state.showsOnlyAuthor,
                                  onSelected: (_) => controller.toggleOnlyAuthor(),
                                ),
                                FilterChip(
                                  label: const Text('倒序'),
                                  selected: state.reverseOrder,
                                  onSelected: (_) => controller.toggleReverseOrder(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            if (state.isLoading)
                              const LinearProgressIndicator(minHeight: 2),
                            if (state.isLoading) const SizedBox(height: 20),
                            if (state.errorMessage != null)
                              Text(
                                state.errorMessage!,
                                style: const TextStyle(
                                  color: AppTheme.secondaryInk,
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      sliver: state.displayedReplies.isEmpty
                          ? const SliverToBoxAdapter(
                              child: Card(
                                child: Padding(
                                  padding: EdgeInsets.all(18),
                                  child: Text(
                                    '当前筛选条件下没有回复，后续这里会继续接入真实 thread detail 状态机。',
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
                                  final int replyIndex = index ~/ 2;
                                  if (index.isOdd) {
                                    return const SizedBox(height: 12);
                                  }
                                  return _ReplyCard(reply: state.displayedReplies[replyIndex]);
                                },
                                childCount: (state.displayedReplies.length * 2) - 1,
                              ),
                            ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                        child: _PaginationBar(
                          currentPage: payload.currentPage,
                          totalPages: payload.totalPages,
                          onPrevious: () => controller.goToPage(payload.currentPage - 1),
                          onNext: () => controller.goToPage(payload.currentPage + 1),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _ReplyCard extends StatelessWidget {
  const _ReplyCard({
    required this.reply,
  });

  final Reply reply;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    reply.author,
                    style: const TextStyle(
                      color: AppTheme.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (reply.floor != null)
                  Text(
                    '${reply.floor}楼',
                    style: const TextStyle(
                      color: AppTheme.secondaryInk,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(width: 8),
                Text(
                  reply.createdAt,
                  style: const TextStyle(
                    color: AppTheme.secondaryInk,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              reply.body,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.currentPage,
    required this.totalPages,
    required this.onPrevious,
    required this.onNext,
  });

  final int currentPage;
  final int totalPages;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: <Widget>[
            IconButton(
              onPressed: currentPage > 1 ? onPrevious : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '$currentPage / $totalPages',
                    style: const TextStyle(
                      color: AppTheme.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'PAGE',
                    style: TextStyle(
                      color: AppTheme.secondaryInk,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: currentPage < totalPages ? onNext : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}
