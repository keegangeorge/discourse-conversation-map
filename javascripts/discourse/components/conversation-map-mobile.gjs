import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { modifier } from "ember-modifier";
import dConcatClass from "discourse/ui-kit/helpers/d-concat-class";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import dLoadingSpinner from "discourse/ui-kit/helpers/d-loading-spinner";
import { i18n } from "discourse-i18n";
import ConversationMapPreview from "./conversation-map-preview.gjs";
import ConversationMapSurface from "./conversation-map-surface.gjs";

export default class ConversationMapMobile extends Component {
  @service appEvents;

  progressControl = modifier((element, [compact]) => {
    if (!compact) {
      return;
    }
    let progress;
    let previousTabIndex;
    const frame = requestAnimationFrame(() => {
      progress = element
        .closest(".topic-navigation")
        ?.querySelector("#topic-progress");
      if (!progress) {
        return;
      }
      previousTabIndex = progress.getAttribute("tabindex");
      progress.setAttribute("tabindex", "0");
      progress.addEventListener("keydown", this.openFromKeyboard);
      if (this.#restoreFocus) {
        progress.focus({ preventScroll: true });
        this.#restoreFocus = false;
      }
    });
    return () => {
      cancelAnimationFrame(frame);
      progress?.removeEventListener("keydown", this.openFromKeyboard);
      if (progress) {
        if (previousTabIndex === null) {
          progress.removeAttribute("tabindex");
        } else {
          progress.setAttribute("tabindex", previousTabIndex);
        }
      }
    };
  });

  replaceBackButton = modifier((element) => {
    const navigation = element.closest(".topic-navigation");
    navigation?.classList.add("has-conversation-map-return");
    return () => navigation?.classList.remove("has-conversation-map-return");
  });

  showSheet = modifier((element) => {
    const navigation = element.closest(".topic-navigation");
    navigation?.classList.add("has-conversation-map-sheet");
    document.body.classList.add("has-conversation-map-sheet");
    element.showModal();
    element
      .querySelector(".conversation-map__track")
      ?.focus({ preventScroll: true });
    return () => {
      element.close();
      navigation?.classList.remove("has-conversation-map-sheet");
      document.body.classList.remove("has-conversation-map-sheet");
      this.#restoreFocus = true;
    };
  });

  #restoreFocus = false;

  @action
  openFromKeyboard(event) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      this.appEvents.trigger("topic:toggle-progress-expansion");
    }
  }

  @action
  cancel(event) {
    event.preventDefault();
    this.args.map.dismissMobile();
  }

  @action
  backdrop(event) {
    if (event.target === event.currentTarget) {
      const rect = event.currentTarget.getBoundingClientRect();
      if (
        event.clientY < rect.top ||
        event.clientX < rect.left ||
        event.clientX > rect.right
      ) {
        this.args.map.dismissMobile();
      }
    }
  }

  <template>
    <span
      class="conversation-map-mount"
      {{this.progressControl @compact}}
    ></span>
    {{#if (and @active @map.expanded)}}
      <dialog
        aria-label={{i18n (themePrefix "title")}}
        class="conversation-map-sheet"
        tabindex="-1"
        {{this.showSheet}}
        {{on "cancel" this.cancel}}
        {{on "click" this.backdrop}}
      >
        <header class="conversation-map-sheet__header">
          <h2>{{i18n (themePrefix "title")}}</h2>
          <button
            aria-label={{i18n (themePrefix "close")}}
            class="conversation-map__close"
            type="button"
            {{on "click" @map.dismissMobile}}
          >{{dIcon "xmark"}}</button>
        </header>
        <div class="conversation-map-sheet__content">
          <section
            aria-label={{@map.positionLabel}}
            class="conversation-map-sheet__preview"
            id={{@map.previewId}}
          >
            <div
              class="conversation-map-sheet__position"
            >{{@map.positionLabel}}</div>
            <ConversationMapPreview @map={{@map}} />
            <div class="conversation-map-sheet__steps">
              <button
                aria-label={{i18n (themePrefix "previous")}}
                class="btn btn-default"
                type="button"
                {{on "click" (fn @map.step -1)}}
              >{{dIcon "chevron-up"}}</button>
              <span>{{i18n (themePrefix "mobile_hint")}}</span>
              <button
                aria-label={{i18n (themePrefix "next")}}
                class="btn btn-default"
                type="button"
                {{on "click" (fn @map.step 1)}}
              >{{dIcon "chevron-down"}}</button>
            </div>
          </section>
          <div class="conversation-map is-mobile is-expanded">
            <ConversationMapSurface @map={{@map}} />
          </div>
        </div>
        <div
          aria-label={{i18n (themePrefix "mobile_landmarks")}}
          class="conversation-map__landmarks"
        >
          {{#each @map.landmarks as |mark|}}
            <button
              class={{dConcatClass "conversation-map__chip" mark.kind}}
              title={{mark.label}}
              type="button"
              {{on "click" (fn @map.previewLandmark mark.index)}}
            >{{dIcon mark.icon}} #{{mark.number}}</button>
          {{/each}}
        </div>
        <footer class="conversation-map-sheet__footer">
          {{#if @map.returning}}
            <button
              class="btn btn-default"
              disabled={{@map.navigating}}
              type="button"
              {{on "click" @map.returnToReading}}
            >{{@map.returnLabel}}</button>
          {{else}}
            <span>{{@map.staysLabel}}</span>
          {{/if}}
          <button
            class="btn btn-primary conversation-map-sheet__open"
            disabled={{or
              @map.loading
              @map.failed
              @map.navigating
              (not @map.preview)
            }}
            type="button"
            {{on "click" @map.readPost}}
          >
            {{#if @map.navigating}}{{dLoadingSpinner size="small"}}{{/if}}
            {{i18n (themePrefix "open_post")}}
          </button>
        </footer>
      </dialog>
    {{else if (and @compact @map.returning)}}
      <button
        class="conversation-map-mobile-return btn btn-default"
        disabled={{@map.navigating}}
        type="button"
        {{on "click" @map.returnToReading}}
        {{this.replaceBackButton}}
      >{{dIcon "arrow-rotate-left"}} {{@map.returnLabel}}</button>
    {{/if}}
  </template>
}
