# flutter_forumhub

This directory contains the Flutter rebuild of `ForumHub`.

Current phase:

- Phase 1 skeleton
- shared app shell
- initial domain models
- placeholder tabs for Home, Community, History, and User

## Next Local Steps

Once Flutter SDK is available on this machine:

```sh
cd flutter_forumhub
flutter pub get
flutter create . --platforms=ios,android
flutter run
```

If `flutter create .` would overwrite files, run it carefully and keep the existing `lib/` structure from this repo.
