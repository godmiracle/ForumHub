class UnimplementedSourceException implements Exception {
  const UnimplementedSourceException(this.message);

  final String message;

  @override
  String toString() => 'UnimplementedSourceException: $message';
}
