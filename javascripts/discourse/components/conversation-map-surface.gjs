import { get } from "@ember/helper";
import { on } from "@ember/modifier";
import dConcatClass from "discourse/ui-kit/helpers/d-concat-class";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import dPointerDrag from "discourse/ui-kit/modifiers/d-pointer-drag";
import { i18n } from "discourse-i18n";

export default <template>
  <div class="conversation-map__surface">
    <div
      aria-controls={{if @map.expanded @map.previewId}}
      aria-label={{@map.mapLabel}}
      aria-orientation="vertical"
      aria-valuemax={{@map.stream.length}}
      aria-valuemin="1"
      aria-valuenow={{@map.sliderValue}}
      aria-valuetext={{@map.positionLabel}}
      class="conversation-map__track"
      role="slider"
      tabindex="0"
      {{on "pointermove" @map.move}}
      {{dPointerDrag
        onDragStart=@map.startScrub
        onDrag=@map.moveScrub
        onDragEnd=@map.endScrub
        onDragCancel=@map.cancelScrub
        draggingClass="is-scrubbing"
        stopPropagation=true
        bodyClass="is-conversation-map-scrubbing"
      }}
      {{on "keydown" @map.keydown}}
    >
      <div aria-hidden="true" class="conversation-map__texture">
        {{#each @map.ticks as |tick|}}<span
            class="conversation-map__tick"
            style={{tick.style}}
          ></span>{{/each}}
        {{#each @map.media as |post|}}
          <span
            class={{dConcatClass
              "conversation-map__media"
              (if post.images.length "has-image")
            }}
            style={{post.style}}
          >
            {{#if post.images.length}}<img
                alt=""
                loading="lazy"
                src={{get (get post.images "0") "url"}}
              />{{else}}{{dIcon post.icon}}{{/if}}
            {{#if (gt post.imageCount 1)}}<span
                class="conversation-map__media-count"
              >{{post.imageCount}}</span>{{/if}}
          </span>
        {{/each}}
        {{#if @map.lastReadStyle}}<span
            class="conversation-map__last-read"
            style={{@map.lastReadStyle}}
            title={{i18n (themePrefix "last_visit")}}
          ></span>{{/if}}
        <span
          class="conversation-map__viewport"
          style={{@map.viewportStyle}}
        ></span>
        {{#if @map.showPreviewCursor}}<span
            class="conversation-map__cursor"
            style={{@map.cursorStyle}}
          ></span>{{/if}}
      </div>
    </div>
    <div class="conversation-map__landmark-controls">
      {{#each @map.landmarks as |mark|}}<button
          aria-label={{mark.label}}
          class={{dConcatClass "conversation-map__landmark" mark.kind}}
          style={{mark.style}}
          title={{mark.label}}
          type="button"
          {{on "click" (fn @map.selectLandmark mark.index)}}
        >{{dIcon mark.icon}}</button>{{/each}}
    </div>
  </div>
</template>
