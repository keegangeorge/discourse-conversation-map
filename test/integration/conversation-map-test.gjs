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
  waitUntil,
} from "@ember/test-helpers";
import { module, test } from "qunit";
import sinon from "sinon";
import DiscourseURL from "discourse/lib/url";
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
    urlForPostNumber(number) {
      return `/t/test/123/${number}`;
    },
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

  test("desktop landmarks are direct navigation controls", async function (assert) {
    const model = topic();
    model.bookmarks = [
      { bookmarkable_id: 105, bookmarkable_type: "Post", post_number: 4 },
    ];
    const jump = sinon.stub(DiscourseURL, "jumpToPost");
    const url = sinon.stub(DiscourseURL, "replaceState");
    try {
      await render(
        <template>
          <div class="timeline-container">
            <div class="timeline-scrollarea"><div class="timeline-scroller">Native
                timeline</div></div>
            <ConversationMap @topic={{model}} />
          </div>
        </template>
      );
      await waitFor(".conversation-map__landmark");

      assert
        .dom(".conversation-map__landmark")
        .hasTagName("button", "the marker exposes its action directly");
      assert
        .dom(".conversation-map__landmark")
        .hasAttribute(
          "aria-label",
          "Bookmarked",
          "the marker has an accessible name"
        );
      assert.strictEqual(
        find(".conversation-map__track").contains(
          find(".conversation-map__landmark")
        ),
        false,
        "the button is not nested inside the slider widget"
      );

      await click(".conversation-map__landmark");
      await waitUntil(() => jump.called);

      assert
        .dom(".conversation-map__track")
        .hasAttribute(
          "aria-valuenow",
          "2",
          "the clicked marker selects its post"
        );
      assert.true(jump.calledOnceWith(4), "the marker navigates to its post");
      assert.true(url.calledOnce, "the marker updates the topic URL");
    } finally {
      jump.restore();
      url.restore();
    }
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
  test("a topic change cancels old measurements without disabling new scroll updates", async function (assert) {
    const model = tracked(topic());
    await render(
      <template>
        <div class="timeline-container"><div
            class="timeline-scrollarea"
          ></div><ConversationMap @topic={{model.value}} /></div>
      </template>
    );
    await waitFor(".conversation-map__track");
    const events = this.owner.lookup("service:app-events");
    const clock = sinon.useFakeTimers({
      toFake: ["requestAnimationFrame", "cancelAnimationFrame"],
    });
    try {
      events.trigger("topic:current-post-scrolled", {
        postIndex: 3,
        percent: 1,
      });
      model.value = { ...topic(), id: 124 };
      await settled();
      clock.tick(20);
      await settled();
      events.trigger("topic:current-post-scrolled", {
        postIndex: 2,
        percent: 0.5,
      });
      clock.tick(20);
      await settled();
      assert
        .dom(".conversation-map__track")
        .hasAttribute(
          "aria-valuenow",
          "2",
          "the new topic keeps receiving reading-position updates"
        );
    } finally {
      clock.restore();
    }
  });
  test("unchanged loaded posts do not churn when the stream exceeds the preview cache", async function (assert) {
    const model = topic();
    model.postStream.posts = Array.from({ length: 161 }, (_, index) => ({
      id: 1000 + index,
      post_number: index + 1,
      cooked: `<p>Post ${index}</p>`,
      username: "sam",
    }));
    model.postStream.stream = model.postStream.posts.map((post) => post.id);
    await render(
      <template>
        <div class="timeline-container"><div
            class="timeline-scrollarea"
          ></div><ConversationMap @topic={{model}} /></div>
      </template>
    );
    await waitFor(".conversation-map__track");
    const createElement = sinon.spy(document, "createElement");
    const events = this.owner.lookup("service:app-events");
    try {
      events.trigger("topic:current-post-scrolled", {
        postIndex: 2,
        percent: 0.1,
      });
      await waitUntil(
        () =>
          find(".conversation-map__track").getAttribute("aria-valuenow") === "2"
      );
      assert.strictEqual(
        createElement.withArgs("template").callCount,
        0,
        "unchanged posts are not reparsed because of cache eviction"
      );
      model.postStream.posts[0].cooked = "<p>Edited opening</p>";
      events.trigger("topic:current-post-scrolled", {
        postIndex: 3,
        percent: 0.2,
      });
      await waitUntil(
        () =>
          find(".conversation-map__track").getAttribute("aria-valuenow") === "3"
      );
      assert.strictEqual(
        createElement.withArgs("template").callCount,
        1,
        "an actual post edit is still inspected"
      );
    } finally {
      createElement.restore();
    }
  });
});
