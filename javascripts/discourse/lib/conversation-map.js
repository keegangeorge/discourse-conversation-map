export function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

export function percentForIndex(index, length) {
  return (
    (clamp(index, 0, Math.max(length - 1, 0)) / Math.max(length - 1, 1)) * 100
  );
}

export function indexForPointer(y, top, height, length) {
  return Math.round(
    clamp((y - top) / Math.max(height, 1), 0, 1) * Math.max(length - 1, 0)
  );
}

export function sampleIds(stream, limit, knownIds = new Set()) {
  if (limit < 1 || !stream.length) {
    return [];
  }
  const ids = new Set();
  for (let i = 0; i < limit; i++) {
    const index = Math.round(
      (i * (stream.length - 1)) / Math.max(limit - 1, 1)
    );
    const id = stream[index];
    if (!knownIds.has(id)) {
      ids.add(id);
    }
  }
  return [...ids];
}

export function inspectPost(post, origin) {
  const neutral = {
    id: post.id,
    number: post.post_number,
    username: "",
    date: null,
    text: "",
    images: [],
    imageCount: 0,
    kind: "post",
    actionCode: null,
  };
  if (post.hidden || post.deleted_at) {
    return neutral;
  }
  // A detached template is inert, including resource loads from excluded media.
  const template = document.createElement("template");
  template.innerHTML = post.cooked || "";
  const doc = template.content;
  // Hidden content must never become a thumbnail or appear in an excerpt.
  doc
    .querySelectorAll(
      ".spoiler, .spoiled, details, script, style, iframe, .onebox, [hidden], [aria-hidden='true']"
    )
    .forEach((el) => el.remove());
  const images = [];
  if (!post.hidden && !post.deleted_at) {
    for (const img of doc.querySelectorAll("img:not(.emoji):not(.avatar)")) {
      if (img.width && img.width < 100) {
        continue;
      }
      const candidates = (img.getAttribute("srcset") || "")
        .split(",")
        .map((candidate) => candidate.trim().match(/^(\S+)\s+([\d.]+)(w|x)$/))
        .filter(Boolean)
        .map(([, url, size, unit]) => ({
          url,
          width: Number(size) * (unit === "x" ? img.width || 690 : 1),
        }))
        .sort((a, b) => a.width - b.width);
      const source =
        (
          candidates.find((candidate) => candidate.width >= 320) ||
          candidates.at(-1)
        )?.url || img.getAttribute("src");
      if (!source) {
        continue;
      }
      try {
        const url = new URL(source, origin);
        // Reuse local thumbnails only. Don't load third-party tracking images on hover.
        if (
          url.origin === origin &&
          /^https?:$/.test(url.protocol) &&
          !images.some((image) => image.url === url.href)
        ) {
          images.push({ url: url.href, alt: img.getAttribute("alt") || "" });
        }
      } catch {
        // Malformed image URLs are not previewable.
      }
    }
  }
  const hasCode = Boolean(doc.querySelector("pre code"));
  const hasVideo = Boolean(doc.querySelector("video, audio"));
  doc
    .querySelectorAll("img, video, audio, pre, .meta")
    .forEach((el) => el.remove());
  const text =
    post.hidden || post.deleted_at
      ? ""
      : doc.textContent.replace(/\s+/g, " ").trim().slice(0, 260);
  return {
    id: post.id,
    number: post.post_number,
    username: post.username,
    date: post.created_at,
    text,
    images: images.slice(0, 3),
    imageCount: images.length,
    kind:
      images.length > 1
        ? "gallery"
        : images.length
          ? "image"
          : hasCode
            ? "code"
            : hasVideo
              ? "video"
              : "post",
    actionCode: post.action_code,
  };
}
