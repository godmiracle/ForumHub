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
- GIF support currently relies on a shared remote image pipeline plus WebKit-backed playback.
- The pipeline uses in-memory reuse and local file caching to reduce repeated full GIF downloads.
- Thread snapshot export uses static image loading behavior and should not depend on interactive preview state.

## Current Risks

- GIF loading is more expensive than static image loading and is sensitive to cancellation timing.
- Source image hosts may use unstable caching or anti-hotlink protections.
- Preview, zoom, save, and inline rendering all share the same asset assumptions, so regressions can cascade across multiple surfaces.

