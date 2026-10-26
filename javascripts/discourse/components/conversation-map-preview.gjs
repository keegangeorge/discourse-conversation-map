import dLoadingSpinner from "discourse/ui-kit/helpers/d-loading-spinner";
import { i18n } from "discourse-i18n";

export default <template>
  <div
    aria-busy={{if @map.loading "true" "false"}}
    class="conversation-map__body"
  >
    {{#if @map.loading}}
      <div class="conversation-map__status">
        {{dLoadingSpinner size="small"}}
        <span class="sr-only">{{i18n (themePrefix "loading")}}</span>
      </div>
    {{else if @map.failed}}<p class="conversation-map__status">{{i18n
          (themePrefix "unavailable")
        }}</p>
    {{else if @map.preview}}
      <div class="conversation-map__byline"><strong
        >{{@map.preview.username}}</strong><span>#{{@map.preview.number}}
          ·
          {{@map.previewDate}}</span></div>
      {{#if @map.preview.images.length}}<div
          class="conversation-map__photos"
        >{{#each @map.preview.images as |image|}}<img
              alt={{image.alt}}
              src={{image.url}}
            />{{/each}}</div>{{/if}}
      <p class="conversation-map__excerpt">{{@map.preview.text}}</p>

    {{/if}}

  </div>
</template>
