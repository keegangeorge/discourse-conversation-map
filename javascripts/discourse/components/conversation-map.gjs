import Component from "@glimmer/component";
import { cached, tracked } from "@glimmer/tracking";
import { fn, get } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { trustHTML } from "@ember/template";
import { modifier } from "ember-modifier";
import { ajax } from "discourse/lib/ajax";
import { headerOffset } from "discourse/lib/offset-calculator";
import DiscourseURL from "discourse/lib/url";
import Topic from "discourse/models/topic";
import dConcatClass from "discourse/ui-kit/helpers/d-concat-class";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import dLoadingSpinner from "discourse/ui-kit/helpers/d-loading-spinner";
import dPointerDrag from "discourse/ui-kit/modifiers/d-pointer-drag";
import { i18n } from "discourse-i18n";
import {
  clamp,
  indexForPointer,
  inspectPost,
  percentForIndex,
  sampleIds,
} from "../lib/conversation-map.js";
import { mapSession } from "../lib/conversation-map-session.js";
import PreviewLoader from "../lib/preview-loader.js";
import ScrubQueue from "../lib/scrub-queue.js";
import { navigateToPost } from "../lib/topic-navigation.js";

let mapSequence = 0;

export default class ConversationMap extends Component {
  @service appEvents;

  @tracked target = null;
  @tracked expanded = false;
  @tracked pinned = false;
  @tracked scrubbing = false;
  @tracked selectedIndex = null;
  @tracked currentNumber = 1;
  @tracked currentIndex = 0;
  @tracked visibleCount = 1;
  @tracked revision = 0;
  @tracked loading = false;
  @tracked failed = false;
  @tracked returning = null;
  @tracked lastReadId = null;
  previewId = `conversation-map-preview-${++mapSequence}`;

  // Stream refreshes invalidate eligibility even when its value stays true.
  // Only a topic change should reset a gesture or its reading anchor.
  setup = modifier((element, [topicId]) => {
    const generation = ++this.#generation;
    this.#eligibilityKey = null;
    this.#frame = requestAnimationFrame(() => {
      if (generation !== this.#generation) {
        return;
      }
      this.#topicId = topicId;
      this.#cache.clear();
      this.#cooked.clear();
      this.#sampled = false;
      this._streamSnapshot = null;
      this.returning = mapSession(
        topicId,
        this.args.topic.last_read_post_id
      ).anchor;
      this.expanded = false;
      this.pinned = false;
      this.scrubbing = false;
      this.selectedIndex = null;
      this.lastReadId = mapSession(
        topicId,
        this.args.topic.last_read_post_id
      ).lastReadId;
      this.currentNumber =
        this.args.topic.current_post_number || this.args.topic.currentPost || 1;
      const area = element
        .closest(".timeline-container")
        ?.querySelector(".timeline-scrollarea");
      this.target = area;
      this.collectPosts();
      this.currentIndex = Math.max(
        0,
        this.stream.indexOf(
          this.args.topic.postStream.posts.find(
            (post) => post.post_number === this.currentNumber
          )?.id
        )
      );
    });
    this.appEvents.on("topic:current-post-scrolled", this.scrolled);
    return () => {
      this.#topicId = null;
      this.#invalidate();
      cancelAnimationFrame(this.#frame);
      cancelAnimationFrame(this.#scrollFrame);
      cancelAnimationFrame(this.#stateFrame);
      this.#clearTimers();
      this.#scrubQueue.cancel();
      this.appEvents.off("topic:current-post-scrolled", this.scrolled);
    };
  });

  watchEligibility = modifier((_element, [enabled, filterKey]) => {
    const key = `${this.args.topic.id}:${enabled}:${filterKey}`;
    if (this.#eligibilityKey && this.#eligibilityKey !== key) {
      this.#invalidate();
      const generation = this.#generation;
      cancelAnimationFrame(this.#stateFrame);
      this.#stateFrame = requestAnimationFrame(() => {
        if (generation === this.#generation) {
          this.close();
          this.#sampled = false;
        }
      });
    }
    this.#eligibilityKey = key;
  });
  mountMap = modifier((element, [expanded]) => {
    this.#mapElement = element;
    const parent = element.parentElement;
    parent.classList.add("has-conversation-map");
    parent.classList.toggle("is-conversation-map-expanded", expanded);
    parent.addEventListener("pointerenter", this.enter);
    parent.addEventListener("pointerleave", this.leave);
    element.addEventListener("focusin", this.focusEntered);
    element.addEventListener("focusout", this.focusLeft);
    return () => {
      parent.removeEventListener("pointerenter", this.enter);
      parent.removeEventListener("pointerleave", this.leave);
      element.removeEventListener("focusin", this.focusEntered);
      element.removeEventListener("focusout", this.focusLeft);
      this.#mapElement = null;
      parent.classList.remove(
        "has-conversation-map",
        "is-conversation-map-expanded"
      );
    };
  });

  #cache = new Map();
  #cooked = new Map();
  #topicId;
  #sampled = false;
  #openTimer;
  #closeTimer;
  #previewTimer;
  #frame;
  #generation = 0;
  #eligibilityKey;
  #navigationRequest;
  #mapElement;
  #hovered = false;
  #scrollFrame;
  #stateFrame;
  #lastScrollEvent;
  #loader = new PreviewLoader((ids) => {
    const xhr = ajax(`/t/${this.#topicId}/posts.json`, {
      data: { post_ids: ids, include_suggested: false },
      ignoreUnsent: false,
    });
    const response = xhr.then((json) => json?.post_stream?.posts || []);
    response.abort = () => xhr.abort();
    return response;
  });
  #selection = 0;

  #scrubBounds = null;

  #scrubQueue = new ScrubQueue((request, isCurrent) =>
    this.#performNavigation(request, isCurrent)
  );
  @tracked _streamSnapshot = null;

  get enabled() {
    const stream = this.args.topic.postStream;
    return (
      !this.args.fullscreen &&
      !stream.isMegaTopic &&
      !this.args.topic.is_nested_view &&
      this.filterKey === "{}" &&
      stream.stream.length >= settings.minimum_posts
    );
  }

  get filterKey() {
    return JSON.stringify(this.args.topic.postStream.streamFilters || {});
  }

  @cached
  get streamIndex() {
    return new Map(this.stream.map((id, index) => [id, index]));
  }

  get stream() {
    return this._streamSnapshot || this.args.topic.postStream.stream;
  }

  get readingLabel() {
    return i18n(themePrefix("reading"), {
      current: this.currentIndex + 1,
      total: this.stream.length,
    });
  }

  get positionLabel() {
    return i18n(themePrefix("position"), {
      current: (this.selectedIndex ?? this.currentIndex) + 1,
      total: this.stream.length,
    });
  }

  get staysLabel() {
    return i18n(themePrefix(this.returning ? "reading_position" : "stays"), {
      number: this.currentNumber,
    });
  }

  get returnLabel() {
    return i18n(themePrefix("return_to"), { number: this.returning?.number });
  }

  get currentStyle() {
    const height = clamp(
      (this.visibleCount / Math.max(this.stream.length, 1)) * 100,
      4,
      18
    );
    return trustHTML(
      `top: ${Math.min(percentForIndex(this.currentIndex, this.stream.length), 100 - height)}%; height: ${height}%;`
    );
  }

  get cursorStyle() {
    return this.positionStyle(this.selectedIndex ?? this.currentIndex);
  }

  get lastReadStyle() {
    const index = this.streamIndex.get(this.lastReadId) ?? -1;
    return index >= 0 ? this.positionStyle(index) : null;
  }

  @cached
  get ticks() {
    const count = Math.min(this.stream.length, 70);
    return Array.from({ length: count }, (_, index) => ({
      key: index,
      style: trustHTML(`top: ${percentForIndex(index, count)}%;`),
    }));
  }

  get inspectedPosts() {
    return this.revision ? [...this.#cache.values()] : [];
  }

  get sliderValue() {
    return (this.selectedIndex ?? this.currentIndex) + 1;
  }

  @cached
  get landmarks() {
    const landmarks = new Map();
    const add = (id, kind, icon, number) => {
      const index = this.streamIndex.get(Number(id)) ?? -1;
      if (index >= 0) {
        landmarks.set(Number(id), {
          id: Number(id),
          index,
          number,
          kind,
          icon,
          label: i18n(themePrefix(kind)),
          style: this.positionStyle(index),
        });
      }
    };
    for (const post of this.inspectedPosts) {
      if (/^(assigned|reassigned)/.test(post.actionCode || "")) {
        add(post.id, "assigned", "user-plus", post.number);
      }
    }
    for (const [id, assignment] of Object.entries(
      this.args.topic.indirectly_assigned_to || {}
    )) {
      add(id, "assigned", "user-plus", assignment.post_number);
    }
    for (const bookmark of this.args.topic.bookmarks || []) {
      if (bookmark.bookmarkable_type === "Post") {
        add(
          bookmark.bookmarkable_id,
          "saved",
          "bookmark",
          bookmark.post_number
        );
      }
    }
    for (const answer of this.args.topic.accepted_answers || []) {
      add(answer.id, "answer", "check", answer.post_number);
    }
    return [...landmarks.values()]
      .sort((a, b) => {
        const priority = { answer: 0, saved: 1, assigned: 2 };
        return priority[a.kind] - priority[b.kind] || a.index - b.index;
      })
      .slice(0, 32)
      .sort((a, b) => a.index - b.index);
  }

  @cached
  get media() {
    const occupied = new Set();
    return this.inspectedPosts
      .filter((post) => post.kind !== "post")
      .map((post) => {
        const index = this.streamIndex.get(post.id) ?? -1;
        return {
          ...post,
          index,
          style: this.positionStyle(index),
          icon:
            post.kind === "code"
              ? "code"
              : post.kind === "video"
                ? "play"
                : "image",
        };
      })
      .filter((post) => post.index >= 0)
      .sort((a, b) => a.index - b.index)
      .filter((post) => {
        const bucket = Math.floor(
          percentForIndex(post.index, this.stream.length) / 9
        );
        if (occupied.has(bucket)) {
          return false;
        }
        occupied.add(bucket);
        return true;
      });
  }

  get preview() {
    return this.inspectedPosts.find(
      (post) => post.id === this.stream[this.selectedIndex]
    );
  }

  get previewLabel() {
    const mark = this.landmarks.find(
      (item) => item.index === this.selectedIndex
    );
    if (mark) {
      return mark.label;
    }
    return this.preview?.kind === "gallery"
      ? i18n(themePrefix("gallery"), { count: this.preview.imageCount })
      : i18n(themePrefix(this.preview?.kind || "post"));
  }

  get previewDate() {
    return this.preview?.date
      ? new Intl.DateTimeFormat(document.documentElement.lang || "en", {
          month: "short",
          day: "numeric",
        }).format(new Date(this.preview.date))
      : "";
  }

  get assignee() {
    return (
      this.args.topic.assigned_to_user?.username ||
      this.args.topic.assigned_to_group?.name
    );
  }

  positionStyle(index) {
    return trustHTML(`top: ${percentForIndex(index, this.stream.length)}%;`);
  }

  collectPosts() {
    let changed = false;
    for (const post of this.args.topic.postStream.posts) {
      changed = this.#remember(post) || changed;
    }
    if (changed) {
      this.revision++;
    }
  }

  @action
  scrolled(event) {
    this.#lastScrollEvent = event;
    if (!this.#scrollFrame) {
      this.#scrollFrame = requestAnimationFrame(() => {
        this.#scrollFrame = null;
        if (!this.#topicId) {
          return;
        }
        const liveStream = this.args.topic.postStream;
        const id = liveStream.stream[this.#lastScrollEvent.postIndex - 1];
        this.currentIndex = this.streamIndex.get(id) ?? this.currentIndex;
        const post = liveStream.posts.find((item) => item.id === id);
        this.currentNumber = post?.post_number || this.currentNumber;
        this.visibleCount =
          liveStream.posts.filter((item) => {
            const rect = document
              .getElementById(`post_${item.post_number}`)
              ?.getBoundingClientRect();
            return (
              rect &&
              rect.bottom > headerOffset() &&
              rect.top < window.innerHeight
            );
          }).length || 1;
        this.collectPosts();
      });
    }
  }

  @action
  enter(event) {
    this.#hovered = true;
    clearTimeout(this.#closeTimer);
    if (event.pointerType === "touch" || this.expanded) {
      return;
    }
    clearTimeout(this.#openTimer);
    this.#openTimer = setTimeout(() => this.open(), 180);
  }

  @action
  leave() {
    this.#hovered = false;
    clearTimeout(this.#openTimer);
    if (!this.pinned && !this.scrubbing) {
      this.#closeTimer = setTimeout(() => {
        if (
          !this.#hovered &&
          !this.#mapElement?.contains(document.activeElement)
        ) {
          this.close();
        }
      }, 320);
    }
  }

  @action
  focusEntered() {
    clearTimeout(this.#closeTimer);
  }

  @action
  focusLeft() {
    if (!this.#hovered) {
      this.leave();
    }
  }

  @action
  open() {
    if (!this.enabled || !this.#topicId) {
      return;
    }
    clearTimeout(this.#closeTimer);
    if (!this.expanded) {
      this._streamSnapshot = [...this.args.topic.postStream.stream];
      this.expanded = true;
      this.collectPosts();
      this.select(this.currentIndex);
      this.#sample();
    }
  }

  @action
  close() {
    const restoreFocus = this.#mapElement
      ?.querySelector(".conversation-map__preview")
      ?.contains(document.activeElement);
    this.#clearTimers();
    this.#scrubQueue.cancel();
    this.#navigationRequest?.abort();
    this.#loader.cancel();
    this.#sampled = false;
    this.scrubbing = false;
    this.#scrubBounds = null;
    this.expanded = false;
    this.pinned = false;
    this._streamSnapshot = null;
    this.selectedIndex = null;
    this.#selection++;
    if (restoreFocus) {
      this.target
        ?.querySelector(".conversation-map__track")
        ?.focus({ preventScroll: true });
    }
  }

  @action
  move(event) {
    if (!this.expanded || this.pinned || event.pointerType === "touch") {
      return;
    }
    const rect = event.currentTarget.getBoundingClientRect();
    this.select(
      indexForPointer(event.clientY, rect.top, rect.height, this.stream.length)
    );
  }

  @action
  startScrub(event) {
    this.#scrubBounds = event.currentTarget.getBoundingClientRect();
    this.open();
    this.pinned = true;
    this.scrubbing = true;
    this.#rememberReturnAnchor();
    this.#updateScrub(event, true);
  }

  @action
  moveScrub(event) {
    if (this.scrubbing) {
      this.#updateScrub(event);
    }
  }

  @action
  endScrub(event) {
    if (this.scrubbing) {
      this.#updateScrub(event, true);
      this.scrubbing = false;
      this.#scrubBounds = null;
    }
  }

  @action
  cancelScrub() {
    this.#scrubQueue.cancel();
    this.#navigationRequest?.abort();
    this.scrubbing = false;
    this.#scrubBounds = null;
  }

  @action
  select(index) {
    index = clamp(index, 0, this.stream.length - 1);
    if (index === this.selectedIndex) {
      return;
    }
    this.selectedIndex = index;
    this.failed = false;
    clearTimeout(this.#previewTimer);
    const selection = ++this.#selection;
    const id = this.stream[index];
    this.loading = !this.#cache.has(id);
    if (this.loading) {
      this.#previewTimer = setTimeout(async () => {
        try {
          await this.#fetch([id]);
          if (selection === this.#selection && this.#topicId) {
            this.failed = !this.#cache.has(id);
          }
        } catch {
          if (selection === this.#selection && this.#topicId) {
            this.failed = true;
          }
        } finally {
          if (selection === this.#selection && this.#topicId) {
            this.loading = false;
          }
        }
      }, 180);
    }
  }

  @action
  previewLandmark(index) {
    this.select(index);
  }

  @action
  selectLandmark(index) {
    this.open();
    this.pinned = true;
    this.#rememberReturnAnchor();
    this.select(index);
    this.#scrubQueue.request({ id: this.stream[index] }, true);
  }

  @action
  step(delta) {
    this.select((this.selectedIndex ?? this.currentIndex) + delta);
  }

  @action
  keydown(event) {
    if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      this.close();
      this.target
        ?.querySelector(".conversation-map__track")
        ?.focus({ preventScroll: true });
      return;
    }
    if (event.target !== event.currentTarget) {
      return;
    }
    const steps = {
      ArrowDown: 1,
      ArrowUp: -1,
      ArrowRight: 1,
      ArrowLeft: -1,
      PageDown: 10,
      PageUp: -10,
    };
    if (
      event.key in steps ||
      ["Home", "End", "Enter", " "].includes(event.key)
    ) {
      event.preventDefault();
      event.stopPropagation();
      const wasOpen = this.expanded;
      this.open();
      this.pinned = true;
      if (event.key in steps) {
        this.step(steps[event.key]);
      } else if (event.key === "Home" || event.key === "End") {
        this.select(event.key === "Home" ? 0 : this.stream.length - 1);
      } else if (event.key === "Enter" && wasOpen && this.preview) {
        this.readPost();
      }
    }
  }

  @action
  readPost() {
    if (!this.preview || this.loading) {
      return;
    }
    const number = this.preview.number;
    this.#rememberReturnAnchor();
    this.close();
    this.#scrubQueue.request({ number }, true);
  }

  @action
  returnToReading() {
    const anchor = this.returning;
    if (!anchor) {
      return;
    }
    this.close();
    this.#scrubQueue.request(
      { number: anchor.number, offset: anchor.offset, returnAnchor: anchor },
      true
    );
  }

  #rememberReturnAnchor() {
    if (!this.returning) {
      const top = headerOffset();
      const visible = this.args.topic.postStream.posts
        .map((post) => ({
          number: post.post_number,
          rect: document
            .getElementById(`post_${post.post_number}`)
            ?.getBoundingClientRect(),
        }))
        .filter(
          ({ rect }) =>
            rect && rect.bottom > top && rect.top < window.innerHeight
        )
        .sort((a, b) => a.rect.top - b.rect.top)[0];
      this.returning = {
        number: visible?.number ?? this.currentNumber,
        offset: visible?.rect.top,
      };
      mapSession(this.#topicId).anchor = this.returning;
    }
  }

  #updateScrub(event, immediate = false) {
    const bounds = this.#scrubBounds;
    const index = indexForPointer(
      event.clientY,
      bounds.top,
      bounds.height,
      this.stream.length
    );
    this.select(index);
    this.#scrubQueue.request({ id: this.stream[index] }, immediate);
  }

  async #performNavigation(request, isCurrent) {
    const generation = this.#generation;
    const valid = () =>
      isCurrent() &&
      generation === this.#generation &&
      this.enabled &&
      !!this.#topicId;
    try {
      if (request.id) {
        await this.#fetch([request.id]);
        if (!valid()) {
          return;
        }
        const post = this.#cache.get(request.id);
        if (!post || !this.args.topic.postStream.stream.includes(request.id)) {
          this.failed = true;
          return;
        }
        request = { ...request, number: post.number };
      }
      const success = await this.#navigate(request, valid);
      if (
        success &&
        valid() &&
        request.returnAnchor === this.returning &&
        request.returnAnchor
      ) {
        mapSession(this.args.topic.id).anchor = null;
        this.returning = null;
      }
    } catch {
      if (valid()) {
        this.failed = true;
      }
    }
  }

  #invalidate() {
    this.#generation++;
    this.#selection++;
    this.#clearTimers();
    this.#scrubQueue.cancel();
    this.#navigationRequest?.abort();
    this.#loader.cancel();
  }

  #clearTimers() {
    clearTimeout(this.#openTimer);
    clearTimeout(this.#closeTimer);
    clearTimeout(this.#previewTimer);
  }

  #remember(post) {
    if (!post?.id) {
      return;
    }
    if (post.hidden || post.deleted_at) {
      const deleted = this.#cache.delete(post.id);
      this.#cooked.delete(post.id);
      return deleted;
    }
    const cachedPost = this.#cache.get(post.id);
    if (
      this.#cooked.get(post.id) !== post.cooked ||
      cachedPost?.username !== post.username ||
      cachedPost?.date !== post.created_at ||
      cachedPost?.actionCode !== post.action_code
    ) {
      this.#cache.set(post.id, inspectPost(post, window.location.origin));
      this.#cooked.set(post.id, post.cooked);
      if (this.#cache.size > 160) {
        const oldest = this.#cache.keys().next().value;
        this.#cache.delete(oldest);
        this.#cooked.delete(oldest);
      }
      return true;
    }
    return false;
  }

  async #fetch(ids) {
    const generation = this.#generation;
    ids = ids.filter((id) => id && !this.#cache.has(id));
    if (!ids.length || !this.#topicId || !this.enabled) {
      return;
    }
    const posts = await this.#loader.load(ids);
    if (generation !== this.#generation || this.isDestroying || !this.enabled) {
      return;
    }
    let changed = false;
    for (const post of posts) {
      if (post) {
        changed = this.#remember(post) || changed;
      }
    }
    if (changed) {
      this.revision++;
    }
  }

  async #sample() {
    if (this.#sampled) {
      return;
    }
    this.#sampled = true;
    const ids = sampleIds(
      this.stream,
      settings.sample_posts,
      new Set(this.#cache.keys())
    );
    const landmarks = this.landmarks.slice(0, 8).map((mark) => mark.id);
    try {
      await this.#fetch([...new Set([...ids, ...landmarks])]);
    } catch {
      // Sampling is optional; a failed request must leave native navigation usable.
    }
  }

  async #navigate(request, isCurrent) {
    const topic = this.args.topic;
    const stream = topic.postStream;
    try {
      const success = await navigateToPost(
        request,
        {
          isLoaded: (number) =>
            stream.posts.some(
              (post) =>
                post.post_number === number && !post.hidden && !post.deleted_at
            ),
          load: async (number) => {
            const xhr = ajax(`/t/${topic.id}/${number}.json`, {
              data: { include_suggested: false },
              ignoreUnsent: false,
            });
            this.#navigationRequest = xhr;
            try {
              const json = await xhr;
              if (
                !json?.post_stream?.posts?.some(
                  (post) =>
                    post.post_number === number &&
                    !post.hidden &&
                    !post.deleted_at
                )
              ) {
                throw new Error("Post is unavailable");
              }
              return json;
            } finally {
              if (this.#navigationRequest === xhr) {
                this.#navigationRequest = null;
              }
            }
          },
          commit: (json) => {
            topic.updateFromJson(json);
            stream.updateFromJson(json.post_stream);
            stream.setProperties({
              timelineLookup: json.timeline_lookup,
              loaded: true,
            });
          },
          jump: (number, offset) => {
            DiscourseURL.replaceState(topic.urlForPostNumber(number));
            DiscourseURL.jumpToPost(number, { originalTopOffset: offset });
          },
        },
        isCurrent
      );
      if (success) {
        await Topic.applyTransformations([topic]);
      }
      return success;
    } catch {
      if (isCurrent()) {
        this.failed = true;
        this.expanded = true;
        this.pinned = true;
      }
      return false;
    }
  }

  <template>
    <span
      class="conversation-map-mount"
      {{this.setup @topic.id}}
      {{this.watchEligibility this.enabled this.filterKey}}
    ></span>
    {{#if (and this.enabled this.target)}}
      {{#in-element this.target insertBefore=null}}
        <div
          class={{dConcatClass
            "conversation-map"
            (if this.expanded "is-expanded")
          }}
          {{this.mountMap this.expanded}}
        >
          <div class="conversation-map__surface">
            <div
              aria-controls={{if this.expanded this.previewId}}
              aria-label={{i18n (themePrefix "map_label")}}
              aria-orientation="vertical"
              aria-valuemax={{this.stream.length}}
              aria-valuemin="1"
              aria-valuenow={{this.sliderValue}}
              aria-valuetext={{this.positionLabel}}
              class="conversation-map__track"
              role="slider"
              tabindex="0"
              {{on "pointermove" this.move}}
              {{dPointerDrag
                onDragStart=this.startScrub
                onDrag=this.moveScrub
                onDragEnd=this.endScrub
                onDragCancel=this.cancelScrub
                draggingClass="is-scrubbing"
                stopPropagation=true
              }}
              {{on "keydown" this.keydown}}
            >
              <div aria-hidden="true" class="conversation-map__texture">
                {{#each this.ticks as |tick|}}<span
                    class="conversation-map__tick"
                    style={{tick.style}}
                  ></span>{{/each}}
                {{#each this.media as |post|}}
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
                {{#if this.lastReadStyle}}<span
                    class="conversation-map__last-read"
                    style={{this.lastReadStyle}}
                    title={{i18n (themePrefix "last_visit")}}
                  ></span>{{/if}}
                <span
                  class="conversation-map__viewport"
                  style={{this.currentStyle}}
                ></span>
                {{#each this.landmarks as |mark|}}<span
                    class={{dConcatClass
                      "conversation-map__landmark"
                      mark.kind
                    }}
                    style={{mark.style}}
                    title={{mark.label}}
                  >{{dIcon mark.icon}}</span>{{/each}}
                {{#if this.expanded}}<span
                    class="conversation-map__cursor"
                    style={{this.cursorStyle}}
                  ></span>{{/if}}
              </div>
            </div>
          </div>
          <span
            class="conversation-map__reading"
            style={{this.currentStyle}}
          >{{this.readingLabel}}</span>
          {{#if this.expanded}}
            <section
              aria-busy={{if this.loading "true" "false"}}
              aria-label={{i18n (themePrefix "title")}}
              class="conversation-map__preview"
              id={{this.previewId}}
              role="dialog"
              tabindex="-1"
              {{on "keydown" this.keydown}}
            >
              <header class="conversation-map__header"><span
                >{{this.previewLabel}}</span><button
                  aria-label={{i18n (themePrefix "close")}}
                  class="conversation-map__close"
                  type="button"
                  {{on "click" this.close}}
                >{{dIcon "xmark"}}</button></header>
              <div
                aria-label={{i18n (themePrefix "landmarks")}}
                class="conversation-map__landmarks"
              >
                {{#each this.landmarks as |mark|}}<button
                    class={{dConcatClass "conversation-map__chip" mark.kind}}
                    title={{mark.label}}
                    type="button"
                    {{on "pointerenter" (fn this.previewLandmark mark.index)}}
                    {{on "focus" (fn this.previewLandmark mark.index)}}
                    {{on "click" (fn this.selectLandmark mark.index)}}
                  >{{dIcon mark.icon}} #{{mark.number}}</button>{{/each}}
              </div>
              {{#if this.loading}}
                <div class="conversation-map__status">
                  {{dLoadingSpinner size="small"}}
                  <span class="sr-only">{{i18n (themePrefix "loading")}}</span>
                </div>
              {{else if this.failed}}<p class="conversation-map__status">{{i18n
                    (themePrefix "unavailable")
                  }}</p>
              {{else if this.preview}}
                <div class="conversation-map__byline"><strong
                  >{{this.preview.username}}</strong><span
                  >#{{this.preview.number}} · {{this.previewDate}}</span></div>
                {{#if this.preview.images.length}}<div
                    class="conversation-map__photos"
                  >{{#each this.preview.images as |image|}}<img
                        alt={{image.alt}}
                        src={{image.url}}
                      />{{/each}}</div>{{/if}}
                <p class="conversation-map__excerpt">{{this.preview.text}}</p>

              {{/if}}
              <footer class="conversation-map__footer"><span
                >{{this.staysLabel}}</span><div><button
                    aria-label={{i18n (themePrefix "previous")}}
                    type="button"
                    {{on "click" (fn this.step -1)}}
                  >{{dIcon "chevron-up"}}</button><button
                    aria-label={{i18n (themePrefix "next")}}
                    type="button"
                    {{on "click" (fn this.step 1)}}
                  >{{dIcon "chevron-down"}}</button></div></footer>
              {{#if this.assignee}}<div
                  class="conversation-map__assigned"
                >{{dIcon "user-plus"}}
                  {{i18n (themePrefix "assigned")}}:
                  {{this.assignee}}</div>{{/if}}

            </section>
          {{/if}}
        </div>
      {{/in-element}}
    {{/if}}
    {{#if this.returning}}<button
        class="conversation-map-return btn btn-default"
        type="button"
        {{on "click" this.returnToReading}}
      >{{dIcon "arrow-rotate-left"}} {{this.returnLabel}}</button>{{/if}}
  </template>
}
