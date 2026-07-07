import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_forumhub/data/providers/forum_repository_provider.dart';
import 'package:flutter_forumhub/domain/models/forum_source.dart';
import 'package:flutter_forumhub/domain/models/reply.dart';
import 'package:flutter_forumhub/domain/models/thread_detail_payload.dart';
import 'package:flutter_forumhub/domain/repositories/forum_repository.dart';
import 'package:flutter_forumhub/session/nga/nga_session_epoch.dart';

final AutoDisposeNotifierProviderFamily<ThreadDetailController, ThreadDetailState,
        ThreadDetailArgs> threadDetailControllerProvider =
    NotifierProvider.autoDispose.family<ThreadDetailController, ThreadDetailState,
        ThreadDetailArgs>(
  ThreadDetailController.new,
);

class ThreadDetailController
    extends AutoDisposeFamilyNotifier<ThreadDetailState, ThreadDetailArgs> {
  late final ForumRepository _repository;

  @override
  ThreadDetailState build(ThreadDetailArgs arg) {
    ref.watch(ngaSessionEpochProvider);
    _repository = ref.read(forumRepositoryProvider);
    Future<void>.microtask(() => _loadPage(page: 1, arg: arg));

    return ThreadDetailState(
      payload: null,
      showsOnlyAuthor: false,
      reverseOrder: false,
      isLoading: true,
      errorMessage: null,
    );
  }

  Future<void> _loadPage({
    required int page,
    required ThreadDetailArgs arg,
  }) async {
    state = state.copyWith(
      isLoading: true,
      clearsErrorMessage: true,
    );
    try {
      final ThreadDetailPayload payload = await _repository.threadDetail(
        arg.source,
        arg.threadId,
        page: page,
      );
      state = state.copyWith(
        payload: payload,
        isLoading: false,
        clearsErrorMessage: true,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: error.toString(),
      );
    }
  }

  Future<void> goToPage(int page) async {
    final ThreadDetailPayload? payload = state.payload;
    if (payload == null) {
      return;
    }

    final int targetPage = page.clamp(1, payload.totalPages);
    if (targetPage == payload.currentPage) {
      return;
    }

    await _loadPage(
      page: targetPage,
      arg: ThreadDetailArgs(
        source: payload.thread.source,
        threadId: payload.thread.id,
      ),
    );
  }

  void toggleOnlyAuthor() {
    state = state.copyWith(showsOnlyAuthor: !state.showsOnlyAuthor);
  }

  void toggleReverseOrder() {
    state = state.copyWith(reverseOrder: !state.reverseOrder);
  }

  Future<void> reload(ThreadDetailArgs arg) {
    final int page = state.payload?.currentPage ?? 1;
    return _loadPage(page: page, arg: arg);
  }
}

class ThreadDetailArgs {
  const ThreadDetailArgs({
    required this.source,
    required this.threadId,
  });

  final ForumSource source;
  final String threadId;
}

class ThreadDetailState {
  const ThreadDetailState({
    required this.payload,
    required this.showsOnlyAuthor,
    required this.reverseOrder,
    required this.isLoading,
    required this.errorMessage,
  });

  final ThreadDetailPayload? payload;
  final bool showsOnlyAuthor;
  final bool reverseOrder;
  final bool isLoading;
  final String? errorMessage;

  List<Reply> get displayedReplies {
    final ThreadDetailPayload? currentPayload = payload;
    if (currentPayload == null) {
      return const <Reply>[];
    }

    Iterable<Reply> replies = currentPayload.replies;
    if (showsOnlyAuthor) {
      replies = replies.where((Reply reply) => reply.author == currentPayload.thread.author);
    }
    if (reverseOrder) {
      replies = replies.toList().reversed;
    }
    return replies.toList();
  }

  ThreadDetailState copyWith({
    ThreadDetailPayload? payload,
    bool clearsPayload = false,
    bool? showsOnlyAuthor,
    bool? reverseOrder,
    bool? isLoading,
    String? errorMessage,
    bool clearsErrorMessage = false,
  }) {
    return ThreadDetailState(
      payload: clearsPayload ? null : (payload ?? this.payload),
      showsOnlyAuthor: showsOnlyAuthor ?? this.showsOnlyAuthor,
      reverseOrder: reverseOrder ?? this.reverseOrder,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearsErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
