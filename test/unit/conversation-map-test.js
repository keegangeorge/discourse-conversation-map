import { module, test } from "qunit";
import {
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

  test("untrusted srcset candidates fall back without relaxing the origin boundary", function (assert) {
    const origin = "https://forum.example";
    const cases = [
      [
        '<img src="/src.png" srcset="https://remote.example/a.png 320w">',
        "/src.png",
        "plain src fallback",
      ],
      [
        '<img src="https://remote.example/src.png" srcset="https://remote.example/a.png 320w, /other.png 640w">',
        "/other.png",
        "another srcset candidate",
      ],
      [
        '<img src="/src.png" srcset="/small.png 100w, https://remote.example/a.png 320w, /large.png 640w">',
        "/small.png",
        "remaining candidates keep ascending order",
      ],
      [
        '<img src="/src.png" srcset="http://[invalid 320w, /valid.png 640w">',
        "/valid.png",
        "malformed URL fallback",
      ],
      [
        '<img src="https://remote.example/src.png" srcset="https://remote.example/a.png 320w">',
        null,
        "all remote stays excluded",
      ],
      [
        '<img src="javascript:alert(1)" srcset="data:image/png;base64,AAAA 320w">',
        null,
        "unsafe schemes stay excluded",
      ],
      [
        '<img src="/src.png" srcset="http://forum.example/a.png 320w, https://forum.example:444/a.png 640w">',
        "/src.png",
        "scheme and port are part of origin",
      ],
    ];
    for (const [cooked, expected, message] of cases) {
      assert.deepEqual(
        inspectPost({ id: 1, cooked }, origin).images.map((image) => image.url),
        expected ? [origin + expected] : [],
        message
      );
    }
  });

  test("srcset keeps its original size preference and handles empty or malformed entries", function (assert) {
    const origin = "https://forum.example";
    const cases = [
      ["/small.png 100w, /chosen.png 400w, /large.png 800w", "/chosen.png"],
      ["/small.png 100w, /largest.png 200w", "/largest.png"],
      ["/chosen.png 1x, /large.png 2x", "/chosen.png"],
      ["/chosen.png .5x, /large.png 2x", "/chosen.png"],
      ["/chosen.png .5x", "/chosen.png"],
      ["/chosen.png 1.x, /large.png 2x", "/chosen.png"],
      ["", "/src.png"],
      ["bad descriptor, , /wrong.png nope", "/src.png"],
    ];
    for (const [srcset, expected] of cases) {
      const post = inspectPost(
        {
          id: 1,
          cooked: `<img width="690" src="/src.png" srcset="${srcset}" alt="Photo">`,
        },
        origin
      );
      assert.deepEqual(
        post.images,
        [{ url: origin + expected, alt: "Photo" }],
        srcset || "empty srcset"
      );
    }
  });

  test("commas within unsafe srcset URLs never become local candidates", function (assert) {
    const origin = "https://forum.example";
    for (const srcset of [
      "data:image/png;base64,AAAA 320w",
      "data:image/svg+xml,local.png 320w",
      "data:image/svg+xml,&nbsp;local.png 320w",
      "https://remote.example/a.png,&nbsp;local.png 320w",
      "data:image/svg+xml,&#x2003;local.png 320w",
      "https://remote.example/a,b.png 320w",
    ]) {
      assert.deepEqual(
        inspectPost(
          {
            id: 1,
            cooked: `<img src="javascript:alert(1)" srcset="${srcset}">`,
          },
          origin
        ).images,
        [],
        srcset
      );
      assert.deepEqual(
        inspectPost(
          { id: 1, cooked: `<img src="/safe.png" srcset="${srcset}">` },
          origin
        ).images.map((image) => image.url),
        [origin + "/safe.png"],
        "only the explicit safe fallback is used"
      );
    }
    const post = inspectPost(
      {
        id: 1,
        cooked:
          '<img src="/src.png" srcset="https://remote.example/a.png 320w,/local.png 640w">',
      },
      origin
    );
    assert.strictEqual(
      post.images[0].url,
      origin + "/local.png",
      "separator whitespace is optional"
    );
  });

  test("fallback does not expose concealed media or add extra thumbnails for duplicate images", function (assert) {
    const origin = "https://forum.example";
    const img =
      '<img src="/src.png" srcset="https://remote.example/a.png 320w, /local.png 640w">';
    for (const cooked of [
      `<span class="spoiler">${img}</span>`,
      `<details>${img}</details>`,
      `<div hidden>${img}</div>`,
      `<div aria-hidden="true">${img}</div>`,
    ]) {
      assert.deepEqual(
        inspectPost({ id: 1, cooked }, origin).images,
        [],
        "concealed candidate remains excluded"
      );
    }
    for (const flags of [{ hidden: true }, { deleted_at: "2026-01-01" }]) {
      assert.deepEqual(
        inspectPost({ id: 1, cooked: img, ...flags }, origin).images,
        [],
        "concealed post remains excluded"
      );
    }
    const duplicate = inspectPost({ id: 1, cooked: img + img }, origin);
    assert.deepEqual(
      duplicate.images,
      [{ url: origin + "/local.png", alt: "" }],
      "one accepted candidate per img, duplicates do not trigger another fallback"
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
