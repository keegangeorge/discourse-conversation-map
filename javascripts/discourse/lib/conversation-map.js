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

// These bases come only from Discourse's server-rendered bootstrap, never from
// cooked post markup. Static CDN uploads also retain the site's base URI.
export function configuredUploadBases(setup, origin) {
  const hasRawControls = (value) =>
    Array.from(value).some(
      (char) => char.charCodeAt(0) <= 32 || char.charCodeAt(0) === 127
    );
  const parse = (value) => {
    // Check the raw input first: URL parsing erases dot segments, which must
    // never turn an invalid tenant base into broader root-origin permission.
    if (
      typeof value !== "string" ||
      !/^(https?:)?\/\//i.test(value) ||
      hasRawControls(value) ||
      /%(?:2e|2f|5c|25)/i.test(value) ||
      /(?:^|\/)\.{1,2}(?:\/|$)/.test(value) ||
      /[?#\\]/.test(value)
    ) {
      return null;
    }
    try {
      const url = new URL(value, origin);
      if (
        !/^https?:$/.test(url.protocol) ||
        url.username ||
        url.password ||
        url.search ||
        url.hash
      ) {
        return null;
      }
      return url;
    } catch {
      return null;
    }
  };
  const bases = [];
  // Bootstrap has no database identifier. A raw storage URL may be a shared
  // bucket, so never authorize it. Only explicit CDN namespaces are eligible;
  // root CDN paths (including a shared /uploads root) cannot identify a site.
  const hasNamespace = (url) =>
    url && url.pathname.replace(/\/$/, "") !== "" &&
    url.pathname.replace(/\/$/, "") !== "/uploads";
  const add = (url) => bases.push({
    origin: url.origin,
    prefix: url.pathname.replace(/\/$/, ""),
  });
  const cdn = parse(setup?.cdn);
  const baseUri = setup?.baseUri ?? "";
  if (
    hasNamespace(cdn) &&
    typeof baseUri === "string" &&
    !hasRawControls(baseUri) &&
    (baseUri === "" || /^\/(?!\/)[^?#\\]*$/.test(baseUri)) &&
    !/%|(?:^|\/)\.{1,2}(?:\/|$)/.test(baseUri)
  ) {
    cdn.pathname = `${cdn.pathname.replace(/\/$/, "")}${baseUri.replace(/\/$/, "")}/uploads/`;
    add(cdn);
  }
  if (parse(setup?.s3BaseUrl)) {
    const s3Cdn = parse(setup?.s3Cdn);
    if (hasNamespace(s3Cdn)) {
      add(s3Cdn);
    }
  }
  return bases;
}

function trustedImageURL(source, origin, uploadBases) {
  try {
    const url = new URL(source, origin);
    if (!/^https?:$/.test(url.protocol) || url.username || url.password) {
      return null;
    }
    if (url.origin === origin) {
      return url;
    }
    // Reject ambiguous encoded separators/traversal before matching a tenant
    // namespace. The same parsed origin AND a path boundary must match.
    if (/%(?:2e|2f|5c|25)/i.test(url.pathname) || source.includes("\\")) {
      return null;
    }
    for (const { origin: allowedOrigin, prefix } of uploadBases) {
      if (
        url.origin === allowedOrigin &&
        (url.pathname === prefix || url.pathname.startsWith(`${prefix}/`))
      ) {
        return url;
      }
    }
  } catch {
    // Malformed URLs are not previewable.
  }
  return null;
}

export function inspectPost(post, origin, uploadBases = []) {
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
      const url = trustedImageURL(source, origin, uploadBases);
      if (url && !images.some((image) => image.url === url.href)) {
        images.push({ url: url.href, alt: img.getAttribute("alt") || "" });
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
