import { tracked } from "@glimmer/tracking";
import {
  click,
  find,
  render,
  settled,
  triggerKeyEvent,
  waitFor,
  waitUntil,
} from "@ember/test-helpers";
import { module, test } from "qunit";
import sinon from "sinon";
import DiscourseURL from "discourse/lib/url";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import ConversationMap from "../../discourse/components/conversation-map.gjs";
import {
  mapSession,
  resetMapSessionForUrl,
} from "../../discourse/lib/conversation-map-session.js";

class TopicFixture {
  @tracked is_nested_view = false;
  id = 123;
  current_post_number = 1;
  bookmarks = [
    { bookmarkable_id: 105, bookmarkable_type: "Post", post_number: 4 },
  ];
  accepted_answers = [];
  postStream = {
    stream: [101, 105, 109],
    posts: [
      { id: 101, post_number: 1, cooked: "<p>Opening</p>", username: "sam" },
      { id: 105, post_number: 4, cooked: "<p>Middle</p>", username: "alex" },
      { id: 109, post_number: 9, cooked: "<p>Last</p>", username: "sam" },
    ],
  };

  urlForPostNumber(number) {
    return `/t/test/123/${number}`;
  }
}

module("Integration | Component | ConversationMapMobile", function (hooks) {
  setupRenderingTest(hooks);
  let minimum, sample;
  hooks.beforeEach(function () {
    resetMapSessionForUrl("/latest");
    minimum = settings.minimum_posts;
    sample = settings.sample_posts;
    settings.minimum_posts = 2;
    settings.sample_posts = 0;
  });
  hooks.afterEach(function () {
    resetMapSessionForUrl("/latest");
    settings.minimum_posts = minimum;
    settings.sample_posts = sample;
  });

  test("mobile remains idle until the native progress control is expanded", async function (assert) {
    const topic = new TopicFixture();
    const active = tracked(false);
    await render(
      <template>
        <div class="topic-navigation"><ConversationMap
            @active={{active.value}}
            @compact={{not active.value}}
            @mobile={{true}}
            @topic={{topic}}
          /></div>
      </template>
    );
    assert
      .dom(".conversation-map-sheet")
      .doesNotExist("reading has no extra panel");
    active.value = true;
    await waitFor(".conversation-map-sheet[open]");
    assert
      .dom(".conversation-map__track")
      .isFocused("focus enters the modal sheet");
    assert
      .dom(".conversation-map__track")
      .hasAttribute(
        "aria-orientation",
        "vertical",
        "the rail remains accessible"
      );
    assert
      .dom(".topic-navigation")
      .hasClass(
        "has-conversation-map-sheet",
        "native timeline is replaced only while the sheet is active"
      );
    active.value = false;
    await waitFor(".conversation-map-sheet", { count: 0 });
    assert
      .dom(".topic-navigation")
      .doesNotHaveClass(
        "has-conversation-map-sheet",
        "native styling is restored after dismissal"
      );
  });

  test("keyboard exploration and landmarks do not navigate on mobile", async function (assert) {
    const topic = new TopicFixture();
    const jump = sinon.stub(DiscourseURL, "jumpToPost");
    const url = sinon.stub(DiscourseURL, "replaceState");
    try {
      await render(
        <template>
          <div class="topic-navigation"><ConversationMap
              @active={{true}}
              @mobile={{true}}
              @topic={{topic}}
            /></div>
        </template>
      );
      await waitFor(".conversation-map-sheet[open]");
      await triggerKeyEvent(".conversation-map__track", "keydown", "End");
      assert
        .dom(".conversation-map__byline")
        .includesText("#9", "keyboard changes the preview");
      assert.false(jump.called, "preview does not scroll the topic");
      assert.false(url.called, "preview does not change the URL");
      await click(".conversation-map__chip");
      assert
        .dom(".conversation-map__byline")
        .includesText("#4", "landmark taps only select a preview");
      assert.false(jump.called, "landmark preview does not navigate");
      await click(".conversation-map-sheet__open");

      assert.true(
        jump.calledOnceWith(4),
        "Open post explicitly navigates to the selection"
      );
    } finally {
      jump.restore();
      url.restore();
    }
  });

  test("ineligible topics retain native navigation", async function (assert) {
    const topic = new TopicFixture();
    topic.is_nested_view = true;
    await render(
      <template>
        <div class="topic-navigation"><ConversationMap
            @active={{true}}
            @mobile={{true}}
            @topic={{topic}}
          /></div>
      </template>
    );

    assert
      .dom(".conversation-map-sheet")
      .doesNotExist("nested topics retain the native panel");
    assert
      .dom(".topic-navigation")
      .doesNotHaveClass(
        "has-conversation-map-sheet",
        "the fallback is not hidden"
      );
  });

  test("Escape closes without creating a reading detour", async function (assert) {
    const topic = new TopicFixture();
    const active = tracked(true);
    const events = this.owner.lookup("service:app-events");
    const dismiss = () => {
      active.value = false;
    };
    events.on("topic:toggle-progress-expansion", dismiss);
    try {
      await render(
        <template>
          <div class="topic-navigation"><ConversationMap
              @active={{active.value}}
              @compact={{not active.value}}
              @mobile={{true}}
              @topic={{topic}}
            /></div>
        </template>
      );
      await waitFor(".conversation-map-sheet[open]");
      await triggerKeyEvent(".conversation-map__track", "keydown", "End");
      await triggerKeyEvent(".conversation-map__track", "keydown", "Escape");
      await waitFor(".conversation-map-sheet", { count: 0 });
      assert
        .dom(".conversation-map-mobile-return")
        .doesNotExist("preview-only exploration creates no return anchor");
    } finally {
      events.off("topic:toggle-progress-expansion", dismiss);
    }
  });
  test("one mobile rectangle follows the selected preview", async function (assert) {
    const topic = new TopicFixture();
    await render(
      <template>
        <div class="topic-navigation"><ConversationMap
            @active={{true}}
            @mobile={{true}}
            @topic={{topic}}
          /></div>
      </template>
    );
    await waitFor(".conversation-map-sheet[open]");
    const firstPosition = find(".conversation-map__viewport").style.top;
    await triggerKeyEvent(".conversation-map__track", "keydown", "End");
    assert.notStrictEqual(
      find(".conversation-map__viewport").style.top,
      firstPosition,
      "the rectangle moves to the selected post rather than staying at the reading position"
    );
    assert
      .dom(".conversation-map__cursor")
      .doesNotExist("there is no competing selection line");
    await triggerKeyEvent(".conversation-map__track", "keydown", "Home");
    assert.strictEqual(
      find(".conversation-map__viewport").style.top,
      firstPosition,
      "the rectangle returns to the first preview"
    );
    assert
      .dom(".conversation-map-sheet__footer")
      .includesText("#1", "the footer retains the original reading position");
  });

  test("the map return action temporarily replaces native Back", async function (assert) {
    const topic = new TopicFixture();
    mapSession(topic.id).anchor = { number: 1 };
    const jump = sinon.stub(DiscourseURL, "jumpToPost");
    const url = sinon.stub(DiscourseURL, "replaceState");
    try {
      await render(
        <template>
          <div class="topic-navigation"><div
              class="progress-back-container"
            ><button type="button">Back</button></div><ConversationMap
              @compact={{true}}
              @mobile={{true}}
              @topic={{topic}}
            /></div>
        </template>
      );
      await waitFor(".conversation-map-mobile-return");
      assert
        .dom(".topic-navigation")
        .hasClass(
          "has-conversation-map-return",
          "native Back is suppressed only while the return action exists"
        );
      await click(".conversation-map-mobile-return");
      await waitFor(".topic-navigation:not(.has-conversation-map-return)");
      assert
        .dom(".conversation-map-mobile-return")
        .doesNotExist("the detour action clears after returning");
      assert
        .dom(".progress-back-container")
        .exists("the native control remains intact and can be shown again");
    } finally {
      jump.restore();
      url.restore();
    }
  });
  test("the native progress control opens by keyboard and regains focus on dismissal", async function (assert) {
    const topic = new TopicFixture();
    const active = tracked(false);
    const mounted = tracked(true);
    const events = this.owner.lookup("service:app-events");
    const toggle = () => {
      active.value = !active.value;
    };
    events.on("topic:toggle-progress-expansion", toggle);
    try {
      await render(
        <template>
          <div class="topic-navigation">
            {{#unless active.value}}<nav id="topic-progress" tabindex="-1">1 / 3</nav>{{/unless}}
            {{#if mounted.value}}<ConversationMap
                @active={{active.value}}
                @compact={{not active.value}}
                @mobile={{true}}
                @topic={{topic}}
              />{{/if}}
          </div>
        </template>
      );
      await waitFor("#topic-progress[tabindex='0']");
      await triggerKeyEvent("#topic-progress", "keydown", "Enter");
      await waitFor(".conversation-map-sheet[open]");
      assert
        .dom(".conversation-map__track")
        .isFocused("keyboard activation focuses the map");
      await triggerKeyEvent(".conversation-map__track", "keydown", "Escape");
      await waitUntil(() => find("#topic-progress") === document.activeElement);
      assert
        .dom("#topic-progress")
        .isFocused("Escape restores focus to the remounted progress control");
      await triggerKeyEvent("#topic-progress", "keydown", " ");
      await waitFor(".conversation-map-sheet[open]");
      await click(".conversation-map__close");
      await waitUntil(() => find("#topic-progress") === document.activeElement);
      mounted.value = false;
      await settled();
      assert
        .dom("#topic-progress")
        .hasAttribute(
          "tabindex",
          "-1",
          "teardown restores the native tabindex"
        );
    } finally {
      events.off("topic:toggle-progress-expansion", toggle);
    }
  });
});
