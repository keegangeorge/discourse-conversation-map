import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";

export default class ConversationMapImage extends Component {
  @tracked failure = null;

  get source() {
    const image = this.args.image;
    const failed = this.failure?.image === image ? this.failure.urls : [];
    return [image.url, ...(image.fallbacks || [])].find(
      (url) => !failed.includes(url)
    );
  }

  @action
  failed(event) {
    // An event from a superseded source must not discard the new selection.
    if (event.currentTarget.getAttribute("src") !== this.source) {
      return;
    }
    const image = this.args.image;
    const urls = this.failure?.image === image ? this.failure.urls : [];
    this.failure = { image, urls: [...urls, this.source] };
  }

  <template>
    {{#if this.source}}
      <img
        alt={{@image.alt}}
        src={{this.source}}
        ...attributes
        {{on "error" this.failed}}
      />
    {{/if}}
  </template>
}
