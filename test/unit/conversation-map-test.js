import { module, test } from "qunit";
import {
  configuredUploadBases,
  indexForPointer,
  inspectPost,
  percentForIndex,
  sampleIds,
} from "../../discourse/lib/conversation-map.js";

module("Unit | Lib | conversation-map", function () {
  test("sampling is bounded, evenly spaced, and skips known IDs", function (assert) {
    const stream = Array.from({ length: 10000 }, (_, index) => index + 100);
    const sample = sampleIds(stream, 12);
    assert.strictEqual(sample.length, 12, "only twelve posts are sampled");
    assert.strictEqual(sample[0], 100, "the beginning is included");
    assert.strictEqual(sample.at(-1), 10099, "the end is included");
    assert.deepEqual(
      sampleIds(stream, 12, new Set(sample)),
      [],
      "known posts are not refetched"
    );
    assert.deepEqual(sampleIds(stream, 0), [], "sampling can be disabled");
    assert.deepEqual(
      sampleIds([2, 9], 12),
      [2, 9],
      "short streams are deduplicated"
    );
  });

  test("positions are ordinal and bounded, not post IDs or pixel heights", function (assert) {
    assert.strictEqual(
      percentForIndex(1, 3),
      50,
      "middle stream item is at the midpoint"
    );
    assert.strictEqual(
      percentForIndex(4, 3),
      100,
      "positions clamp at the end"
    );
    assert.strictEqual(
      percentForIndex(0, 1),
      0,
      "single-post streams are finite"
    );
    assert.strictEqual(
      indexForPointer(250, 100, 300, 7),
      3,
      "pointer maps to a stream index"
    );
    assert.strictEqual(
      indexForPointer(-10, 100, 300, 7),
      0,
      "pointer clamps above the rail"
    );
    assert.strictEqual(
      indexForPointer(900, 100, 300, 7),
      6,
      "pointer clamps below the rail"
    );
  });

  test("spoilers and collapsed details never leak into previews", function (assert) {
    const post = inspectPost(
      {
        id: 1,
        cooked:
          '<p>Visible text</p><span class="spoiler">Secret <img src="/secret.jpg"></span><details><summary>More</summary>Hidden <img src="/hidden.jpg"></details>',
      },
      "http://localhost:3000"
    );
    assert.strictEqual(post.text, "Visible text", "hidden text is excluded");
    assert.deepEqual(post.images, [], "hidden media is excluded");
  });

  test("remote images, missing URLs, emoji and avatars are excluded", function (assert) {
    const post = inspectPost(
      {
        id: 1,
        cooked:
          '<img src="https://tracker.example/pixel.jpg"><img><img class="emoji" src="/emoji.png"><img class="avatar" src="/avatar.png"><img width="1" src="/pixel.png"><img src="javascript:alert(1)"><img src="/photo.jpg" alt="Desk" width="690">',
      },
      "http://localhost:3000"
    );
    assert.deepEqual(
      post.images,
      [{ url: "http://localhost:3000/photo.jpg", alt: "Desk" }],
      "only a local content image is eligible"
    );
    assert.strictEqual(
      post.kind,
      "image",
      "the content is classified from real data"
    );
  });

  test("galleries are deduplicated and preview image count is bounded", function (assert) {
    const post = inspectPost(
      {
        id: 1,
        cooked:
          '<img src="/a.jpg"><img src="/a.jpg"><img src="/b.jpg"><img src="/c.jpg"><img src="/d.jpg">',
      },
      "http://localhost:3000"
    );
    assert.strictEqual(
      post.kind,
      "gallery",
      "multiple images form one landmark"
    );
    assert.strictEqual(post.imageCount, 4, "the count reflects unique images");
    assert.strictEqual(
      post.images.length,
      3,
      "at most three images enter the preview"
    );
  });

  test("code is indicated without dumping a large block into an excerpt", function (assert) {
    const post = inspectPost(
      {
        id: 1,
        cooked: "<p>Configuration</p><pre><code>some large block</code></pre>",
      },
      "http://localhost:3000"
    );
    assert.strictEqual(post.kind, "code", "the code landmark is identifiable");
    assert.strictEqual(
      post.text,
      "Configuration",
      "code is excluded from the text excerpt"
    );
  });

  test("hidden posts do not expose text or images", function (assert) {
    const post = inspectPost(
      {
        id: 1,
        hidden: true,
        cooked: '<p>Hidden post</p><img src="/private.jpg">',
      },
      "http://localhost:3000"
    );
    assert.strictEqual(post.text, "", "hidden text stays hidden");
    assert.deepEqual(post.images, [], "hidden images stay hidden");
  });
  test("hidden and deleted code or video stays neutral", function (assert) {
    for (const flags of [{ hidden: true }, { deleted_at: "2026-01-01" }]) {
      const post = inspectPost(
        {
          id: 1,
          ...flags,
          cooked:
            '<pre><code>secret</code></pre><video src="/hidden.mp4"></video><audio src="/hidden.mp3"></audio>',
        },
        "https://forum.example"
      );
      assert.strictEqual(
        post.kind,
        "post",
        "concealed content has no media classification"
      );
      assert.strictEqual(post.text, "", "concealed text is excluded");
      assert.deepEqual(post.images, [], "concealed images are excluded");
    }
  });

  test("configured upload CDN requires the exact origin and tenant path", function (assert) {
    const origin = "https://forum.example";
    const bases = configuredUploadBases(
      {
        s3BaseUrl: "https://bucket.example/site",
        s3Cdn: "https://global.discourse-cdn.com/themecreator",
      },
      origin
    );
    const image = (url, flags = {}, wrapper = "") =>
      inspectPost(
        { id: 1, ...flags, cooked: `${wrapper}<img src="${url}"></span>` },
        origin,
        bases
      ).images;
    assert.strictEqual(
      image("/photo.jpg").length,
      1,
      "same-origin remains allowed"
    );
    assert.strictEqual(
      image("https://global.discourse-cdn.com/themecreator/original/a.jpg")
        .length,
      1,
      "configured tenant is allowed"
    );
    assert.strictEqual(
      image("https://bucket.example/site/original/a.jpg").length,
      1,
      "configured upload storage is allowed"
    );
    for (const url of [
      "https://global.discourse-cdn.com/other/original/a.jpg",
      "https://global.discourse-cdn.com/themecreator-other/a.jpg",
      "https://global.discourse-cdn.com:444/themecreator/a.jpg",
      "http://global.discourse-cdn.com/themecreator/a.jpg",
      "https://tracker.example/themecreator/a.jpg",
      "https://global.discourse-cdn.com/themecreator/../other/a.jpg",
      "https://global.discourse-cdn.com/themecreator/%2f../other/a.jpg",
      "https://global.discourse-cdn.com/themecreator/%252e%252e/a.jpg",
      // eslint-disable-next-line no-script-url -- regression input must remain rejected
      "javascript:alert(1)",
      "data:image/png;base64,aaaa",
    ]) {
      assert.deepEqual(
        image(url),
        [],
        `untrusted or ambiguous URL rejected: ${url}`
      );
    }
    const trusted =
      "https://global.discourse-cdn.com/themecreator/original/a.jpg";
    assert.deepEqual(
      image(trusted, { hidden: true }),
      [],
      "hidden post excluded"
    );
    assert.deepEqual(
      image(trusted, { deleted_at: "2026-01-01" }),
      [],
      "deleted post excluded"
    );
    assert.deepEqual(
      image(trusted, {}, '<span class="spoiler">'),
      [],
      "spoiler excluded"
    );
    assert.deepEqual(
      inspectPost({ id: 1, cooked: `<img src="${trusted}">` }, origin).images,
      [],
      "absent configuration remains same-origin only"
    );
  });

  test("bootstrap upload bases are explicit and safely scoped", function (assert) {
    const origin = "https://forum.example";
    assert.deepEqual(configuredUploadBases(undefined, origin), []);
    assert.deepEqual(
      configuredUploadBases({ s3Cdn: "https://cdn.example/tenant" }, origin),
      [],
      "S3 CDN requires configured upload storage like core bootstrap"
    );
    for (const s3BaseUrl of [
      "garbage",
      // eslint-disable-next-line no-script-url -- invalid bootstrap scheme regression
      "javascript:alert(1)",
      "https://user:pass@cdn.example/site",
      "https://cdn.example/site?redirect=1",
      "https://cdn.example/site#fragment",
      "https://cdn.example/%2ftenant",
    ]) {
      assert.deepEqual(
        configuredUploadBases({ s3BaseUrl }, origin),
        [],
        `invalid bootstrap value ignored: ${s3BaseUrl}`
      );
    }
    for (const invalid of [
      "https://shared.example/themecreator/../",
      "https://shared.example/themecreator/./",
      "https://shared.example/themecreator/%2e%2e/",
      "https://shared.example/themecreator/%2E./",
      ...[9, 10, 13, 0, 32, 127].map(
        (code) =>
          `https://shared.example/themecreator/.${String.fromCharCode(code)}./`
      ),
    ]) {
      assert.deepEqual(
        configuredUploadBases({ s3BaseUrl: invalid }, origin),
        [],
        "raw traversal cannot broaden the storage base"
      );
      const bases = configuredUploadBases(
        { s3BaseUrl: "https://bucket.example/site", s3Cdn: invalid },
        origin
      );
      assert.deepEqual(
        bases,
        ["https://bucket.example/site"],
        "invalid CDN base ignored before normalization"
      );
      assert.deepEqual(
        inspectPost(
          {
            id: 1,
            cooked: '<img src="https://shared.example/other-tenant/a.jpg">',
          },
          origin,
          bases
        ).images,
        [],
        "malformed CDN configuration never permits sibling tenants"
      );
    }
    assert.deepEqual(
      configuredUploadBases(
        { cdn: "//cdn.example/tenant", baseUri: "/forum" },
        origin
      ),
      ["https://cdn.example/tenant/forum/uploads/"],
      "static CDN is restricted to the forum upload subtree"
    );
    assert.deepEqual(
      configuredUploadBases(
        { cdn: "https://cdn.example/tenant", baseUri: "/../other" },
        origin
      ),
      [],
      "ambiguous base URI ignored"
    );
  });

  test("responsive media prefers a small local image candidate", function (assert) {
    const post = inspectPost(
      {
        id: 1,
        cooked:
          '<img src="/original.jpg" srcset="/small.jpg 400w, /large.jpg 1600w" width="1600">',
      },
      "https://forum.example"
    );
    assert.strictEqual(
      post.images[0].url,
      "https://forum.example/small.jpg",
      "the preview avoids the large original when a thumbnail exists"
    );
  });
});
