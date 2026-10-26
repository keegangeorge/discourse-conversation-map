# Conversation map

A Discourse theme component that turns the topic timeline into a hover-expanding conversation minimap.

The normal timeline stays quiet while you read. Hover to inspect the conversation, click a destination to jump, or drag to scrub through the topic. Return to the post and reading offset where you started when you finish exploring.

## Demos

### Desktop

Hover previews, live scrubbing, and return to reading, shown with a macOS-style cursor.

https://github.com/user-attachments/assets/be1d6106-9da8-48a1-9d00-8e15307de04e

### Mobile

Tap the post count, drag to preview, then choose **Open post**. A single selection box follows your finger, and Return restores your reading position without competing with native Back.

https://github.com/user-attachments/assets/8ed25f61-851e-42cd-8f13-b3f8d9b601b0

Videos are GitHub attachments, not files bundled with the component.

## Features

- **Quiet at rest.** The native handle, post count, and dates remain visible, with a small minimap hint beside the count.
- **Hover previews.** Inspect an excerpt, images, or a gallery without scrolling the topic.
- **Direct navigation.** Click the desktop map or a landmark to jump. Hold and drag to move the topic as you scrub, with a grabbing cursor and frame-coalesced pointer updates. Repeated movement over the same post does not restart navigation.
- **Touch-friendly exploration.** Tap the mobile post count to open a bottom sheet. Drag the map or tap landmarks to preview, then choose **Open post** to navigate. Closing the sheet leaves the reading position unchanged.
- **Return to reading.** Restore the original post and its position within the viewport after a detour.
- **Useful landmarks.** See your bookmarks, accepted answers, and assignments when the site provides them.
- **Native loading and colours.** Uses Discourse's spinner and colour palette, including dark mode.
- **Keyboard support.** The map is a vertical slider with an associated preview. Focus remains available when the pointer leaves.

## Install

Requires **Discourse 2026.10.0-latest.1 or newer**. This is an early release; try it on a test theme before enabling it for everyone.

1. Open **Admin → Appearance → Themes & components**.
2. Install a component from this Git repository:

   ```text
   https://github.com/keegangeorge/discourse-conversation-map
   ```

3. Add **Conversation map** to the themes that should use it.

While this repository is private, installation requires Git access to the repository. Do not put GitHub tokens in theme settings or client-side code.

No backend plugin is required. Discourse Solved and Discourse Assign are optional; their landmarks appear only when the corresponding data is available to the current viewer.

## Controls

| Action | Result |
| --- | --- |
| Hover the timeline or post count | Expand the map |
| Move along the map | Preview a position without navigating |
| Hover or focus a landmark | Preview that post |
| Click the map or a landmark | Navigate directly |
| Press and drag | Scrub through the topic; release settles on the latest position |
| Return to #… | Restore the original reading anchor |
| Enter or Space on the collapsed slider | Open the map |
| Arrow keys | Preview the previous or next position |
| Page Up / Page Down | Move ten positions |
| Home / End | Preview the first or last position |
| Enter on an open slider | Navigate to the previewed post |
| Escape | Close the map |

On mobile and narrow layouts, tap the existing post-count control to open the map sheet. Dragging and landmark taps only preview. **Open post** navigates and closes the sheet; **Return to #…** restores the original reading position. The sheet supports keyboard navigation, Escape, focus restoration, safe-area spacing, and landscape layouts.

Reduced-motion preferences are respected.

## Settings

| Setting | Default | Description |
| --- | --- | --- |
| `minimum_posts` | `12` | Keep the native timeline on shorter topics. |
| `sample_posts` | `12` | Maximum evenly spaced posts inspected when opening the map. Set to `0` to disable this sampling. Up to eight known landmarks may also be inspected. |

## Scope and privacy

- Filtered topics, nested topics, mega topics, and topics below `minimum_posts` retain native navigation. Narrow/mobile layouts use the preview sheet instead of the desktop rail.
- The map follows **post sequence**, not elapsed time or rendered post height. Missing post numbers are not assumed to be consecutive.
- It is a sampled overview, not a complete content index. Uninspected positions remain neutral. Crowded media is represented by one landmark per visual band, and at most 32 landmark shortcuts are shown, prioritizing answers and bookmarks.
- Preview metadata is fetched from Discourse's existing permission-checked endpoints. Requests are batched, deduplicated per post, and limited to one preview request at a time. Foreground previews take priority over queued background samples, and up to two nearby posts are prefetched after a selected preview resolves. The in-memory metadata cache holds at most 160 posts, with a separate bounded mapping of up to 512 post IDs to post numbers.
- Preview excerpts and bodies are not persisted in browser storage. A topic-scoped reading anchor survives timeline remounts and is cleared when leaving the topic.
- Hidden/deleted posts, spoilers, collapsed details, oneboxes, emoji, and avatars do not become preview content. Cooked HTML is inspected in an inert template; only plain text and validated image URLs are rendered.
- Only same-origin media is previewed. External and CDN-hosted images are deliberately omitted in this version.
- A smaller responsive image is preferred when available. Otherwise the cooked image URL is reused, so individual image downloads can still be large. Video/audio receives a marker, never autoplay.
- Navigation responses are checked before changing the live topic stream. Clicks, keyboard activation, scrubbing, and Return share the same navigation queue.

The desktop component uses the `timeline-footer-controls-after` outlet and a contained portal into the native `.timeline-scrollarea`. The mobile sheet uses the `topic-navigation` outlet and follows the existing progress control’s expanded state. If the timeline hook is unavailable, the original timeline remains. Disabling the component restores the native UI.

## Development

Use Node.js 22.13.1 or newer and pnpm 10.28.0:

```sh
pnpm install --frozen-lockfile
pnpm lint
```

The `test/` directory contains portable QUnit unit and component-rendering tests. To run them against a Discourse development instance, install the component there, then run from the Discourse checkout:

```sh
bin/qunit --rails-env development --theme-id THEME_COMPONENT_ID \
  --qunit-path /theme-qunit --filter conversation-map
```

GitHub Actions uses Discourse's shared theme workflow for linting and tests against the minimum supported Core tag, `v2026.10.0-latest.1`. This keeps the preview release reproducible and avoids an upstream image-worker socket-path startup failure on the moving `latest` branch. Machine-specific setup scripts, local demo data, screenshots, recordings, and credentials are not part of the repository.

## License

[MIT](LICENSE). Demo photographs are sourced from Unsplash and are not included in the component package.
