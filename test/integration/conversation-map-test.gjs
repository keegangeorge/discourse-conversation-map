import { tracked } from "@glimmer/tracking";
import {
  click,
  find,
  focus,
  render,
  settled,
  triggerEvent,
  triggerKeyEvent,
  waitFor,
} from "@ember/test-helpers";
import { module, test } from "qunit";
import sinon from "sinon";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import ConversationMap from "../../discourse/components/conversation-map.gjs";

class StreamFixture {
  @tracked streamFilters = {};
  stream = [101, 105, 109];
  posts = [
    { id: 101, post_number: 1, cooked: "<p>Opening</p>", username: "sam" },
    { id: 105, post_number: 4, cooked: "<p>Middle</p>", username: "alex" },
    { id: 109, post_number: 9, cooked: "<p>Last</p>", username: "sam" },
  ];
}

function topic() {
  return {
    id: 123,
    current_post_number: 1,
    bookmarks: [],
    accepted_answers: [],
    postStream: new StreamFixture(),
  };
}

module("Integration | Component | ConversationMap", function (hooks) {
  setupRenderingTest(hooks);
  let originalMinimum;
  let originalSample;
  hooks.beforeEach(function () {
    originalMinimum = settings.minimum_posts;
    originalSample = settings.sample_posts;
    settings.minimum_posts = 2;
    settings.sample_posts = 0;
  });
  hooks.afterEach(function () {
    settings.minimum_posts = originalMinimum;
    settings.sample_posts = originalSample;
  });

  test("the vertical slider exposes its preview relationship and closes accessibly", async function (assert) {
    const model = topic();
    await render(
      <template>
        <div class="timeline-container">
          <div class="timeline-scrollarea"><div class="timeline-scroller">Native
              timeline</div></div>
          <ConversationMap @topic={{model}} />
        </div>
      </template>
    );
    await waitFor(".conversation-map__track");
    await triggerKeyEvent(".conversation-map__track", "keydown", "Enter");
    assert
      .dom(".conversation-map__track")
      .hasAttribute(
        "aria-orientation",
        "vertical",
        "the orientation is explicit"
      );
    const id = find(".conversation-map__preview").id;
    assert
      .dom(".conversation-map__track")
      .hasAttribute(
        "aria-controls",
        id,
        "the preview is associated with the slider"
      );
    await focus(".conversation-map__close");
    await click(".conversation-map__close");
    assert
      .dom(".conversation-map__preview")
      .doesNotExist("explicit close dismisses the preview");
    assert
      .dom(".conversation-map__track")
      .isFocused("focus returns to the surviving track");
  });

  test("pointer exit does not remove a keyboard-focused preview", async function (assert) {
    const model = topic();
    await render(
      <template>
        <div class="timeline-container">
          <div class="timeline-scrollarea"><div class="timeline-scroller">Native
              timeline</div></div>
          <ConversationMap @topic={{model}} />
        </div>
      </template>
    );
    await waitFor(".conversation-map__track");
    const clock = sinon.useFakeTimers({
      toFake: ["setTimeout", "clearTimeout"],
    });
    try {
      await triggerEvent(".timeline-scrollarea", "pointerenter", {
        pointerType: "mouse",
      });
      clock.tick(200);
      await settled();
      await focus(".conversation-map__close");
      await triggerEvent(".timeline-scrollarea", "pointerleave", {
        pointerType: "mouse",
      });
      clock.tick(400);
      await settled();
      assert
        .dom(".conversation-map__preview")
        .exists("keyboard focus keeps the hover preview open");
      assert
        .dom(".conversation-map__close")
        .isFocused("the focused control survives pointer exit");
    } finally {
      clock.restore();
    }
  });

  test("filtered topics deactivate the map and restore native navigation", async function (assert) {
    const model = topic();
    await render(
      <template>
        <div class="timeline-container">
          <div class="timeline-scrollarea"><div class="timeline-scroller">Native
              timeline</div></div>
          <ConversationMap @topic={{model}} />
        </div>
      </template>
    );
    await waitFor(".conversation-map__track");
    await triggerKeyEvent(".conversation-map__track", "keydown", "Enter");
    model.postStream.streamFilters = { username_filters: "sam" };
    await settled();
    assert
      .dom(".conversation-map")
      .doesNotExist("a semantic filter change removes the map");
    assert
      .dom(".timeline-scrollarea")
      .doesNotHaveClass("has-conversation-map", "native styling is restored");
    model.postStream.streamFilters = {};
    await waitFor(".conversation-map:not(.is-expanded)");
    assert.dom(".conversation-map").exists("the map can be enabled again");
    assert
      .dom(".conversation-map__preview")
      .doesNotExist("the old preview does not reopen");
  });

  test("non-consecutive post numbers retain ordinal keyboard positions", async function (assert) {
    const model = topic();
    await render(
      <template>
        <div class="timeline-container">
          <div class="timeline-scrollarea"><div class="timeline-scroller">Native
              timeline</div></div>
          <ConversationMap @topic={{model}} />
        </div>
      </template>
    );
    await waitFor(".conversation-map__track");
    await triggerKeyEvent(".conversation-map__track", "keydown", "Enter");
    await triggerKeyEvent(".conversation-map__track", "keydown", "End");
    assert
      .dom(".conversation-map__track")
      .hasAttribute(
        "aria-valuenow",
        "3",
        "the slider uses stream order, not the post number"
      );
    assert
      .dom(".conversation-map__byline")
      .includesText("#9", "the preview still identifies the real post number");
  });
});
