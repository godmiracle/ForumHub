import 'package:flutter_forumhub/domain/models/forum_source.dart';

class ForumChannel {
  const ForumChannel({
    required this.id,
    required this.source,
    required this.title,
    required this.subtitle,
    this.isSubscribed = false,
    this.sortOrder = 0,
  });

  final String id;
  final ForumSource source;
  final String title;
  final String subtitle;
  final bool isSubscribed;
  final int sortOrder;

  ForumChannel copyWith({
    String? id,
    ForumSource? source,
    String? title,
    String? subtitle,
    bool? isSubscribed,
    int? sortOrder,
  }) {
    return ForumChannel(
      id: id ?? this.id,
      source: source ?? this.source,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      isSubscribed: isSubscribed ?? this.isSubscribed,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
