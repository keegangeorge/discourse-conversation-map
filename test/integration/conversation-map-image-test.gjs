import { tracked } from "@glimmer/tracking";
import { render, settled, triggerEvent } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import ConversationMapImage from "../../discourse/components/conversation-map-image.gjs";

module("Integration | Component | ConversationMapImage", function (hooks) {
  setupRenderingTest(hooks);

  test("failed candidates advance once and exhaustion removes the broken image", async function (assert) {
    const image = {
      url: "/images/discourse-logo-sketch.png?preferred",
      fallbacks: [
        "/images/discourse-logo-sketch.png?alternate",
        "/images/discourse-logo-sketch.png?original",
      ],
      alt: "A preserved photo description",
    };
    await render(
      <template><ConversationMapImage @image={{image}} /></template>
    );
    assert.dom("img").hasAttribute("src", image.url);
    assert.dom("img").hasAttribute("alt", image.alt);
    await triggerEvent("img", "error", { bubbles: false });
    assert.dom("img").hasAttribute("src", image.fallbacks[0]);
    await triggerEvent("img", "error", { bubbles: false });
    assert.dom("img").hasAttribute("src", image.fallbacks[1]);
    await triggerEvent("img", "error", { bubbles: false });
    assert.dom("img").doesNotExist("exhaustion never leaves a broken icon");
  });

  test("new image arguments reset failure state even when the preferred URL is reused", async function (assert) {
    class Fixture {
      @tracked
      image = {
        url: "/images/discourse-logo-sketch.png?reused",
        alt: "First post",
      };
    }
    const fixture = new Fixture();
    await render(
      <template><ConversationMapImage @image={{fixture.image}} /></template>
    );
    await triggerEvent("img", "error", { bubbles: false });
    assert.dom("img").doesNotExist();
    fixture.image = {
      url: "/images/discourse-logo-sketch.png?reused",
      alt: "Another post",
    };
    // The same component instance must not inherit the previous failure.
    await settled();
    assert.dom("img").hasAttribute("src", fixture.image.url);
    assert.dom("img").hasAttribute("alt", "Another post");
  });
});
