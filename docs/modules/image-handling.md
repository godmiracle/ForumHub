# Image Handling Module

## Scope

This module covers remote image rendering and related user interactions inside thread detail.

It includes:

- Rich content image parsing
- Static image rendering
- GIF playback
- Image preview
- Save-to-Photos behavior
- Remote image caching and in-flight request reuse
- Snapshot rendering dependencies for long-image export

## Key Files

- `ForumHub/Features/ThreadDetail/ThreadDetailView.swift`
- `ForumHub/Features/ThreadDetail/ThreadSnapshotRenderer.swift`
- `ForumHub/Domain/ForumContent.swift`

## Notes

- Rich content images are rendered from parsed content blocks rather than embedded web content.
- NGA post normalization preserves HTML image sources as shared `[图片] URL` markers before stripping residual HTML, so main-post images follow the same rendering path as reply images.
- GIF support relies on a shared remote image pipeline plus WebKit-backed playback for both inline detail rendering and full-screen preview.
- Inline thread-detail GIF playback is viewport-aware: only a small number of GIFs near the visible region stay animated, while off-screen items fall back to their first frame.
- The pipeline uses in-memory reuse, local file caching, and downsampled preview decoding to reduce repeated downloads and oversized inline image decode work.
- Full-screen preview keeps a lightweight right-side centered action group: save plus close. Outbound link actions stay in the inline long-press menu so the preview surface does not become overcrowded.
- Thread snapshot export uses static image loading behavior and should not depend on interactive preview state.
- NGA avatar URLs from the known legacy `img.nga.178.com` HTTP host are upgraded to HTTPS before `AsyncImage` receives them, so avatar loading remains compatible with App Transport Security without enabling broad HTTP exceptions.

## Current Risks

- GIF loading is more expensive than static image loading and is sensitive to cancellation timing.
- Source image hosts may use unstable caching or anti-hotlink protections.
- Preview, zoom, save, and inline rendering all share the same asset assumptions, so regressions can cascade across multiple surfaces.
