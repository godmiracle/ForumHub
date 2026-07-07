enum ForumSource {
  nga(
    id: 'nga',
    displayName: 'NGA',
    supportsLogin: true,
    supportsNativeFavorites: true,
    supportsReply: true,
  ),
  v2ex(
    id: 'v2ex',
    displayName: 'V2EX',
    supportsLogin: true,
    supportsNativeFavorites: false,
    supportsReply: false,
  ),
  linuxDo(
    id: 'linux_do',
    displayName: 'LINUX DO',
    supportsLogin: true,
    supportsNativeFavorites: false,
    supportsReply: false,
  );

  const ForumSource({
    required this.id,
    required this.displayName,
    required this.supportsLogin,
    required this.supportsNativeFavorites,
    required this.supportsReply,
  });

  final String id;
  final String displayName;
  final bool supportsLogin;
  final bool supportsNativeFavorites;
  final bool supportsReply;
}
