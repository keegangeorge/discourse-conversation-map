import { apiInitializer } from "discourse/lib/api";
import ConversationMap from "../components/conversation-map.gjs";
import { resetMapSessionForUrl } from "../lib/conversation-map-session.js";

export default apiInitializer((api) => {
  api.onPageChange(resetMapSessionForUrl);
  api.renderInOutlet(
    "topic-navigation",
    <template>
      {{#if
        (or @outletArgs.topicProgressExpanded (not @outletArgs.renderTimeline))
      }}
        <ConversationMap
          @active={{@outletArgs.topicProgressExpanded}}
          @compact={{not @outletArgs.renderTimeline}}
          @mobile={{true}}
          @topic={{@outletArgs.topic}}
        />
      {{/if}}
    </template>
  );
  api.renderInOutlet(
    "timeline-footer-controls-after",
    <template>
      <ConversationMap
        @fullscreen={{@outletArgs.fullscreen}}
        @topic={{@outletArgs.model}}
      />
    </template>
  );
});
