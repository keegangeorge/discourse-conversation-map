import { module, test } from "qunit";
import PreviewLoader from "../../discourse/lib/preview-loader.js";

module("Unit | Lib | conversation-map-preview-loader", function () {
  test("overlapping preview and sample requests are deduplicated per post", async function (assert) {
    const calls = [];
    const completions = [];
    const loader = new PreviewLoader((ids) => {
      calls.push(ids);
      return new Promise((resolve) =>
        completions.push(() => resolve(ids.map((id) => ({ id }))))
      );
    });
    const first = loader.load([1, 2]);
    const second = loader.load([2, 3]);
    assert.deepEqual(calls, [[1, 2]], "only one request is in flight");
    completions.shift()();
    assert.deepEqual(
      await first,
      [{ id: 1 }, { id: 2 }],
      "the first batch resolves"
    );
    assert.deepEqual(
      calls,
      [[1, 2], [3]],
      "overlapping post 2 is not fetched twice"
    );
    completions.shift()();
    assert.deepEqual(
      await second,
      [{ id: 2 }, { id: 3 }],
      "the shared result satisfies the second preview"
    );
  });

  test("pending work and batch size remain bounded", async function (assert) {
    const calls = [];
    const loader = new PreviewLoader(async (ids) => {
      calls.push(ids);
      return ids.map((id) => ({ id }));
    });
    const results = await loader.load(
      Array.from({ length: 100 }, (_, index) => index + 1)
    );
    assert.true(
      calls.every((ids) => ids.length <= 20),
      "no batch exceeds twenty posts"
    );
    assert.strictEqual(
      calls.flat().length,
      32,
      "only the latest thirty-two pending posts are requested"
    );
    assert.strictEqual(
      results.filter(Boolean).length,
      32,
      "discarded work resolves without leaking promises"
    );
  });

  test("cancelling resolves waiters, aborts work and ignores stale responses", async function (assert) {
    let resolveOld;
    let aborted = false;
    const loader = new PreviewLoader((ids) => {
      if (ids[0] === 99) {
        return Promise.resolve([{ id: 99 }]);
      }
      const promise = new Promise((resolve) => {
        resolveOld = resolve;
      });
      promise.abort = () => {
        aborted = true;
      };
      return promise;
    });
    const old = loader.load([1]);
    loader.cancel();
    assert.true(aborted, "the active transport is aborted");
    assert.deepEqual(await old, [null], "cancelled waiters settle");
    const fresh = loader.load([99]);
    resolveOld([{ id: 1 }]);
    assert.deepEqual(
      await fresh,
      [{ id: 99 }],
      "a new generation never receives stale data"
    );
  });

  test("network and synchronous failures release the request slot", async function (assert) {
    let failing = true;
    const loader = new PreviewLoader(async (ids) => {
      if (failing) {
        throw new Error("offline");
      }
      return ids.map((id) => ({ id }));
    });
    await assert.rejects(
      loader.load([1]),
      /offline/,
      "network errors reject waiting previews"
    );
    failing = false;
    assert.deepEqual(
      await loader.load([2]),
      [{ id: 2 }],
      "subsequent requests still work"
    );
    const synchronous = new PreviewLoader(() => {
      throw new Error("unavailable");
    });
    await assert.rejects(
      synchronous.load([3]),
      /unavailable/,
      "synchronous errors also settle"
    );
  });
});
