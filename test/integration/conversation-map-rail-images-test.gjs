import {
  focus,
  render,
  triggerEvent,
  triggerKeyEvent,
  waitFor,
} from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import ConversationMap from "../../discourse/components/conversation-map.gjs";

module(
  "Integration | Component | ConversationMap rail images",
  function (hooks) {
    setupRenderingTest(hooks);

    test("rail thumbnails recover trusted alternatives while staying decorative and lazy", async function (assert) {
      const minimum = settings.minimum_posts;
      const sample = settings.sample_posts;
      settings.minimum_posts = 2;
      settings.sample_posts = 0;
      const preferred = "/images/discourse-logo-sketch.png?rail-preferred";
      const alternate = "/images/discourse-logo-sketch.png?rail-original";
      const topic = {
        id: 123,
        current_post_number: 1,
        bookmarks: [],
        accepted_answers: [],
        postStream: {
          streamFilters: {},
          stream: [101, 105, 109],
          posts: [
            {
              id: 101,
              post_number: 1,
              username: "sam",
              cooked: `<p>A rail photo</p><img width="690" src="${alternate}" srcset="${preferred} 400w" alt="Preserved preview description">`,
            },
            {
              id: 105,
              post_number: 4,
              username: "alex",
              cooked: "<p>Middle</p>",
            },
            { id: 109, post_number: 9, username: "sam", cooked: "<p>Last</p>" },
          ],
        },
        urlForPostNumber(number) {
          return `/t/test/123/${number}`;
        },
      };
      try {
        await render(
          <template>
            <div class="timeline-container"><div
                class="timeline-scrollarea"
              ><div class="timeline-scroller">Native timeline</div></div><ConversationMap
                @topic={{topic}}
              /></div>
          </template>
        );
        const rail = ".conversation-map__media img";
        await waitFor(rail);
        assert
          .dom(rail)
          .hasAttribute("src", new URL(preferred, location.origin).href);
        assert.dom(rail).hasAttribute("alt", "");
        assert.dom(rail).hasAttribute("loading", "lazy");
        await triggerEvent(rail, "error", { bubbles: false });
        assert
          .dom(rail)
          .hasAttribute("src", new URL(alternate, location.origin).href);
        await focus(".conversation-map__track");
        await triggerKeyEvent(".conversation-map__track", "keydown", "Home");
        await waitFor(".conversation-map__photos img");
        assert
          .dom(".conversation-map__photos img")
          .hasAttribute("alt", "Preserved preview description");
        assert
          .dom(".conversation-map__photos img")
          .hasAttribute("src", new URL(preferred, location.origin).href);
        await triggerEvent(rail, "error", { bubbles: false });
        assert
          .dom(rail)
          .doesNotExist("exhaustion does not leave a broken thumbnail");
        assert
          .dom(".conversation-map__photos img")
          .exists(
            "rail failure state does not discard the independent preview"
          );
      } finally {
        settings.minimum_posts = minimum;
        settings.sample_posts = sample;
      }
    });
  }
);
