import { module, test } from "qunit";
import {
  mapSession,
  resetMapSessionForUrl,
} from "../../discourse/lib/conversation-map-session.js";

module("Unit | Lib | conversation-map-session", function (hooks) {
  hooks.afterEach(() => resetMapSessionForUrl("/latest"));

  test("reading anchors and last-visit markers survive timeline remounts", function (assert) {
    const session = mapSession(465, 100);
    session.anchor = { number: 27, offset: -120 };
    resetMapSessionForUrl("/t/demo/465/53?preview_theme_id=21");
    const remounted = mapSession(465, 999);
    assert.strictEqual(
      remounted,
      session,
      "the same topic retains its session"
    );
    assert.deepEqual(
      remounted.anchor,
      { number: 27, offset: -120 },
      "the original reading offset is preserved"
    );
    assert.strictEqual(
      remounted.lastReadId,
      100,
      "exploring does not move the original last-visit marker"
    );
  });

  test("leaving the topic clears the anchor", function (assert) {
    mapSession(465, 100).anchor = { number: 27, offset: 12 };
    resetMapSessionForUrl("/latest");
    assert.strictEqual(
      mapSession(465, 100).anchor,
      null,
      "returning later starts a fresh session"
    );
  });

  test("short topic URLs preserve only the matching topic", function (assert) {
    const session = mapSession(465, 100);
    resetMapSessionForUrl("/t/465/53");
    assert.strictEqual(
      mapSession(465, 100),
      session,
      "numeric short URLs identify the topic correctly"
    );
    resetMapSessionForUrl("/t/another-topic/466/2");
    assert.notStrictEqual(
      mapSession(465, 100),
      session,
      "switching topics clears the old session"
    );
  });
});
