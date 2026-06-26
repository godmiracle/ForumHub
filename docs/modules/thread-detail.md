# Thread Detail Module

## Scope

Thread detail is one of the highest-complexity feature areas in ForumHub.

It includes:

- Main post rendering
- Reply rendering
- Pagination
- Only-author filtering
- Reverse ordering
- Floor labels
- Favorites
- Reply composer
- Rich image handling

## Key Files

- `ForumHub/Features/ThreadDetail/ThreadDetailView.swift`
- `ForumHub/Features/ThreadDetail/ThreadSnapshotRenderer.swift`
- `ForumHub/Domain/ForumModels.swift`

## Notes

- Presentation state is layered on top of provider data rather than rewriting repository ordering.
- Reply pagination must protect against duplicate content from source-specific continuation pages.
- Image handling mixes static images, GIF playback, preview, zoom, and save-to-photos behavior.

