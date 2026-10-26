import { module, test } from "qunit";
import sinon from "sinon";
import ScrubQueue from "../../discourse/lib/scrub-queue.js";

module("Unit | Lib | conversation-map-scrub-queue", function () {
  test("rapid pointer positions coalesce to the latest release", async function (assert) {
    let finish;
    const done = new Promise((resolve) => (finish = resolve));
    const calls = [];
    const queue = new ScrubQueue((value) => {
      calls.push(value);
      finish();
    });
    queue.request(10);
    queue.request(20);
    queue.request(30, true);
    await done;
    queue.cancel();
    assert.deepEqual(
      calls,
      [30],
      "release navigates immediately to the newest position"
    );
  });

  test("navigation is serialized and stale work cannot commit", async function (assert) {
    let release;
    let finish;
    const gate = new Promise((resolve) => (release = resolve));
    const done = new Promise((resolve) => (finish = resolve));
    const calls = [];
    const committed = [];
    const queue = new ScrubQueue(async (value, isCurrent) => {
      calls.push(value);
      if (value === 10) {
        await gate;
      }
      if (isCurrent()) {
        committed.push(value);
      }
      if (value === 30) {
        finish();
      }
    });
    queue.request(10, true);
    queue.request(20);
    queue.request(30, true);
    assert.deepEqual(calls, [10], "a second navigation cannot race the first");
    release();
    await done;
    queue.cancel();
    assert.deepEqual(
      calls,
      [10, 30],
      "superseded intermediate positions are skipped"
    );
    assert.deepEqual(
      committed,
      [30],
      "the old response cannot move the topic backward"
    );
  });

  test("cancelling a gesture invalidates pending work", async function (assert) {
    let release;
    let finish;
    const gate = new Promise((resolve) => (release = resolve));
    const done = new Promise((resolve) => (finish = resolve));
    let committed = false;
    const queue = new ScrubQueue(async (_value, isCurrent) => {
      await gate;
      committed = isCurrent();
      finish();
    });
    queue.request(10, true);
    queue.request(20);
    queue.cancel();
    release();
    await done;
    assert.false(
      committed,
      "an escaped or destroyed gesture cannot navigate late"
    );
  });
  test("executor rejection is reported and does not poison later navigation", async function (assert) {
    const errors = [];
    let finish;
    const done = new Promise((resolve) => {
      finish = resolve;
    });
    const queue = new ScrubQueue(
      async (value) => {
        if (value === 1) {
          throw new Error("navigation failed");
        }
        finish(value);
      },
      0,
      (error) => errors.push(error.message)
    );
    queue.request(1, true);
    queue.request(2, true);
    assert.strictEqual(await done, 2, "newer navigation still executes");
    assert.deepEqual(
      errors,
      ["navigation failed"],
      "failure is handled rather than becoming an unhandled rejection"
    );
    queue.cancel();
  });
  test("duplicate destinations preserve the in-flight response and do not navigate twice", async function (assert) {
    let release;
    let finish;
    const gate = new Promise((resolve) => {
      release = resolve;
    });
    const done = new Promise((resolve) => {
      finish = resolve;
    });
    const calls = [];
    const queue = new ScrubQueue(
      async (value, current) => {
        calls.push(value.id);
        await gate;
        assert.true(
          current(),
          "same-position jitter does not invalidate the response"
        );
        finish();
      },
      100,
      () => {},
      (value) => value.id
    );
    queue.request({ id: 3 }, true);
    queue.request({ id: 3 });
    queue.request({ id: 3 }, true);
    release();
    await done;
    await Promise.resolve();
    queue.request({ id: 3 }, true);
    assert.deepEqual(
      calls,
      [3],
      "release does not repeat the committed destination"
    );
    queue.cancel();
  });

  test("a slow request does not add another full throttle interval", async function (assert) {
    const clock = sinon.useFakeTimers({
      toFake: ["Date", "setTimeout", "clearTimeout"],
    });
    let release;
    const gate = new Promise((resolve) => {
      release = resolve;
    });
    const calls = [];
    const queue = new ScrubQueue(async (value) => {
      calls.push(value);
      if (value === 1) {
        await gate;
      }
    }, 100);
    try {
      queue.request(1, true);
      queue.request(2);
      clock.tick(300);
      release();
      await Promise.resolve();
      await Promise.resolve();
      clock.tick(1);
      assert.deepEqual(
        calls,
        [1, 2],
        "the next destination starts as soon as the slow request finishes"
      );
    } finally {
      queue.cancel();
      clock.restore();
    }
  });

  test("failed and cancelled destinations can be requested again", async function (assert) {
    const calls = [];
    const queue = new ScrubQueue(async (value) => {
      calls.push(value);
      return false;
    });
    queue.request(1, true);
    await Promise.resolve();
    queue.request(1, true);
    await Promise.resolve();
    queue.cancel();
    queue.request(1, true);
    await Promise.resolve();
    assert.deepEqual(
      calls,
      [1, 1, 1],
      "failure and cancellation never poison a destination"
    );
    queue.cancel();
  });
});
