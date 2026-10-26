import { module, test } from "qunit";
import ScrubQueue from "../../discourse/lib/scrub-queue.js";
import { navigateToPost } from "../../discourse/lib/topic-navigation.js";

module("Unit | Lib | conversation-map-navigation", function () {
  test("a cancelled response cannot mutate the live stream", async function (assert) {
    let resolve;
    let current = true;
    const commits = [];
    const jumps = [];
    const pending = navigateToPost(
      { number: 53 },
      {
        isLoaded: () => false,
        load: () =>
          new Promise((yes) => {
            resolve = yes;
          }),
        commit: (json) => commits.push(json),
        jump: (number) => jumps.push(number),
      },
      () => current
    );
    current = false;
    resolve({ posts: [53] });
    assert.false(await pending, "the superseded navigation is rejected");
    assert.deepEqual(commits, [], "the late JSON never reaches the model");
    assert.deepEqual(jumps, [], "no URL or scroll mutation occurs");
  });

  test("the window and navigation commit only after the response is current", async function (assert) {
    const events = [];
    const result = await navigateToPost(
      { number: 53, offset: -45 },
      {
        isLoaded: () => false,
        load: async () => ({ posts: [53] }),
        commit: (json) => events.push(["commit", json.posts]),
        jump: (number, offset) => events.push(["jump", number, offset]),
      },
      () => true
    );
    assert.true(result, "the current navigation succeeds");
    assert.deepEqual(
      events,
      [
        ["commit", [53]],
        ["jump", 53, -45],
      ],
      "the loaded window is committed before jumping"
    );
  });

  test("return navigation supersedes an in-flight scrub without racing its commit", async function (assert) {
    let resolveWindow;
    let finishReturn;
    const returned = new Promise((resolve) => {
      finishReturn = resolve;
    });
    const events = [];
    const adapter = {
      isLoaded: (number) => number === 27,
      load: () =>
        new Promise((resolve) => {
          resolveWindow = resolve;
        }),
      commit: () => events.push("stale window"),
      jump: (number) => events.push(number),
    };
    const queue = new ScrubQueue(async (request, current) => {
      await navigateToPost(request, adapter, current);
      if (request.number === 27) {
        finishReturn();
      }
    });
    queue.request({ number: 53 }, true);
    queue.request({ number: 27, offset: -45 }, true);
    resolveWindow({ posts: [53] });
    await returned;
    queue.cancel();
    assert.deepEqual(
      events,
      [27],
      "only the return commits, with no stale stream mutation"
    );
  });

  test("loaded posts need no extra request and inactive maps do nothing", async function (assert) {
    const events = [];
    const adapter = {
      isLoaded: () => true,
      load: () => {
        throw new Error("unexpected load");
      },
      commit: () => {
        throw new Error("unexpected commit");
      },
      jump: (number) => events.push(number),
    };
    assert.true(
      await navigateToPost({ number: 3 }, adapter, () => true),
      "a loaded destination navigates immediately"
    );
    assert.false(
      await navigateToPost({ number: 4 }, adapter, () => false),
      "an inactive map cannot navigate"
    );
    assert.deepEqual(events, [3], "only the active destination was used");
  });
});
