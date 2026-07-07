import 'dart:convert';

Object? ngaDecodeObject(String rawText) {
  final String trimmed = rawText.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final Object? direct = _tryDecode(trimmed);
  if (direct != null) {
    return direct;
  }

  final RegExpMatch? objectMatch = RegExp(r'(\{[\s\S]*\})').firstMatch(trimmed);
  if (objectMatch != null) {
    return _tryDecode(objectMatch.group(1)!);
  }

  final RegExpMatch? listMatch = RegExp(r'(\[[\s\S]*\])').firstMatch(trimmed);
  if (listMatch != null) {
    return _tryDecode(listMatch.group(1)!);
  }

  return null;
}

Object? _tryDecode(String text) {
  try {
    return jsonDecode(text);
  } catch (_) {
    return null;
  }
}

List<Map<String, dynamic>> collectDictionaries(Object? object) {
  final Object? normalized = normalizeNestedObject(object);
  if (normalized is Map<String, dynamic>) {
    return <Map<String, dynamic>>[
      normalized,
      ...normalized.values.expand(collectDictionaries),
    ];
  }

  if (normalized is List<dynamic>) {
    return normalized.expand(collectDictionaries).toList();
  }

  return const <Map<String, dynamic>>[];
}

Object? normalizeNestedObject(Object? object) {
  if (object is String) {
    return ngaDecodeObject(object) ?? object;
  }
  return object;
}

String cleanForumText(String value) {
  var cleaned = value
      .replaceAll('<br>', '\n')
      .replaceAll('<br/>', '\n')
      .replaceAll('<br />', '\n')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");

  cleaned = cleaned.replaceAll(RegExp(r'<[^>]+>'), '');
  cleaned = cleaned.replaceAll('\r', '');
  cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  cleaned = cleaned.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
  return cleaned.trim();
}

bool isUsefulForumValue(String? value) {
  if (value == null) {
    return false;
  }

  final String normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }

  return !<String>{'null', '(null)', 'undefined', '--', 'n/a'}.contains(normalized);
}

String? readString(Map<String, dynamic> dictionary, List<String> keys) {
  for (final String key in keys) {
    final Object? rawValue = dictionary[key];
    if (rawValue is String && rawValue.isNotEmpty) {
      return rawValue;
    }
    if (rawValue is num) {
      return rawValue.toString();
    }
  }
  return null;
}

int? readInt(Map<String, dynamic> dictionary, List<String> keys) {
  for (final String key in keys) {
    final Object? rawValue = dictionary[key];
    if (rawValue is int) {
      return rawValue;
    }
    if (rawValue is num) {
      return rawValue.toInt();
    }
    if (rawValue is String) {
      final int? parsed = int.tryParse(rawValue);
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return null;
}

String? parseAuthorName(Map<String, dynamic> dictionary) {
  final String? direct = readString(
    dictionary,
    const <String>[
      'author',
      'author_name',
      'username',
      'postusername',
      'poster',
      'user_name',
      'nickname',
      'name',
      'lastposter',
    ],
  );
  if (isUsefulForumValue(direct)) {
    return cleanForumText(direct!);
  }

  for (final String key in <String>['user', 'author', 'author_info', 'poster_info', 'userInfo']) {
    final Object? nested = normalizeNestedObject(dictionary[key]);
    if (nested is Map<String, dynamic>) {
      final String? candidate = parseAuthorName(nested);
      if (candidate != null) {
        return candidate;
      }
    }
  }

  return null;
}

String? parseAvatarUrl(Map<String, dynamic> dictionary) {
  final String? direct = readString(
    dictionary,
    const <String>[
      'avatar',
      'avatar_url',
      'avatar_normal',
      'avatar_middle',
      'portrait',
      'face',
    ],
  );
  if (direct != null && _isAbsoluteUrl(direct)) {
    return direct;
  }

  for (final String key in <String>['user', 'author', 'author_info', 'poster_info', 'userInfo']) {
    final Object? nested = normalizeNestedObject(dictionary[key]);
    if (nested is Map<String, dynamic>) {
      final String? candidate = parseAvatarUrl(nested);
      if (candidate != null) {
        return candidate;
      }
    }
  }

  return null;
}

bool _isAbsoluteUrl(String value) {
  final Uri? uri = Uri.tryParse(value);
  return uri != null && uri.hasScheme;
}
