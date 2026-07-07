class NgaLoginState {
  const NgaLoginState({
    required this.uid,
    required this.cid,
    required this.cookieNames,
  });

  final String? uid;
  final String? cid;
  final List<String> cookieNames;

  bool get isLoggedIn {
    if (cid != null && cid!.isNotEmpty) {
      return true;
    }

    if (uid == null || uid!.isEmpty) {
      return false;
    }

    return !uid!.toLowerCase().contains('guest');
  }

  String get cidPreview {
    final String? value = cid;
    if (value == null || value.isEmpty) {
      return '未识别';
    }

    if (value.length <= 10) {
      return value;
    }

    return '${value.substring(0, 6)}...${value.substring(value.length - 4)}';
  }

  String get statusLabel => isLoggedIn ? '已登录' : '未登录';

  NgaLoginState copyWith({
    String? uid,
    String? cid,
    List<String>? cookieNames,
  }) {
    return NgaLoginState(
      uid: uid ?? this.uid,
      cid: cid ?? this.cid,
      cookieNames: cookieNames ?? this.cookieNames,
    );
  }

  factory NgaLoginState.fromMap(Map<Object?, Object?> map) {
    return NgaLoginState(
      uid: map['uid'] as String?,
      cid: map['cid'] as String?,
      cookieNames: (map['cookieNames'] as List<Object?>? ?? const <Object?>[])
          .whereType<String>()
          .toList()
        ..sort(),
    );
  }

  static const NgaLoginState empty = NgaLoginState(
    uid: null,
    cid: null,
    cookieNames: <String>[],
  );
}
