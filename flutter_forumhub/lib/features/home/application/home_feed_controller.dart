import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_forumhub/data/providers/forum_repository_provider.dart';
import 'package:flutter_forumhub/domain/models/forum_channel.dart';
import 'package:flutter_forumhub/domain/models/forum_source.dart';
import 'package:flutter_forumhub/domain/models/forum_thread.dart';
import 'package:flutter_forumhub/domain/repositories/forum_repository.dart';
import 'package:flutter_forumhub/session/nga/nga_session_epoch.dart';

final AutoDisposeNotifierProvider<HomeFeedController, HomeFeedState>
    homeFeedControllerProvider =
    NotifierProvider.autoDispose<HomeFeedController, HomeFeedState>(
  HomeFeedController.new,
);

class HomeFeedController extends AutoDisposeNotifier<HomeFeedState> {
  late final ForumRepository _repository;

  @override
  HomeFeedState build() {
    ref.watch(ngaSessionEpochProvider);
    _repository = ref.read(forumRepositoryProvider);
    const ForumSource initialSource = ForumSource.nga;
    final HomeFeedState emptyState = HomeFeedState(
      availableSources: ForumSource.values,
      selectedSource: initialSource,
      channels: const <ForumChannel>[],
      activeChannel: null,
      threads: const <ForumThread>[],
      isLoading: true,
      errorMessage: null,
    );
    Future<void>.microtask(() => _loadInitial(initialSource));
    return emptyState;
  }

  Future<void> _loadInitial(ForumSource source) async {
    try {
      final List<ForumChannel> channels = await _repository.channelsForSource(source);
      final ForumChannel? activeChannel = channels.isEmpty ? null : channels.first;
      final List<ForumThread> threads = activeChannel == null
          ? const <ForumThread>[]
          : await _repository.threadsForChannel(source, activeChannel.id);

      state = state.copyWith(
        selectedSource: source,
        channels: channels,
        activeChannel: activeChannel,
        threads: threads,
        isLoading: false,
        clearsErrorMessage: true,
      );
    } catch (error) {
      state = state.copyWith(
        channels: const <ForumChannel>[],
        activeChannel: null,
        clearsActiveChannel: true,
        threads: const <ForumThread>[],
        isLoading: false,
        errorMessage: error.toString(),
      );
    }
  }

  Future<void> selectSource(ForumSource source) async {
    if (source == state.selectedSource) {
      return;
    }

    state = state.copyWith(
      selectedSource: source,
      channels: const <ForumChannel>[],
      activeChannel: null,
      clearsActiveChannel: true,
      threads: const <ForumThread>[],
      isLoading: true,
      clearsErrorMessage: true,
    );

    await _loadInitial(source);
  }

  Future<void> selectChannel(ForumChannel channel) async {
    final ForumChannel? activeChannel = state.activeChannel;
    if (activeChannel != null &&
        channel.id == activeChannel.id &&
        channel.source == activeChannel.source) {
      return;
    }

    state = state.copyWith(
      activeChannel: channel,
      threads: const <ForumThread>[],
      isLoading: true,
      clearsErrorMessage: true,
    );

    try {
      final List<ForumThread> threads = await _repository.threadsForChannel(
        state.selectedSource,
        channel.id,
      );

      state = state.copyWith(
        threads: threads,
        isLoading: false,
        clearsErrorMessage: true,
      );
    } catch (error) {
      state = state.copyWith(
        threads: const <ForumThread>[],
        isLoading: false,
        errorMessage: error.toString(),
      );
    }
  }

  Future<void> reload() {
    final ForumChannel? activeChannel = state.activeChannel;
    if (activeChannel != null) {
      return selectChannel(activeChannel);
    }
    return _loadInitial(state.selectedSource);
  }
}

class HomeFeedState {
  const HomeFeedState({
    required this.availableSources,
    required this.selectedSource,
    required this.channels,
    required this.activeChannel,
    required this.threads,
    required this.isLoading,
    required this.errorMessage,
  });

  final List<ForumSource> availableSources;
  final ForumSource selectedSource;
  final List<ForumChannel> channels;
  final ForumChannel? activeChannel;
  final List<ForumThread> threads;
  final bool isLoading;
  final String? errorMessage;

  HomeFeedState copyWith({
    List<ForumSource>? availableSources,
    ForumSource? selectedSource,
    List<ForumChannel>? channels,
    ForumChannel? activeChannel,
    bool clearsActiveChannel = false,
    List<ForumThread>? threads,
    bool? isLoading,
    String? errorMessage,
    bool clearsErrorMessage = false,
  }) {
    return HomeFeedState(
      availableSources: availableSources ?? this.availableSources,
      selectedSource: selectedSource ?? this.selectedSource,
      channels: channels ?? this.channels,
      activeChannel: clearsActiveChannel ? null : (activeChannel ?? this.activeChannel),
      threads: threads ?? this.threads,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearsErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
