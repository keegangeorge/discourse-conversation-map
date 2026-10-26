export default class ScrubQueue {
  #execute;
  #delay;
  #onError;
  #keyFor;
  #latest = null;
  #lastStarted = -Infinity;
  #pending = null;
  #running = false;
  #timer = null;
  #version = 0;
  #immediate = false;

  constructor(
    execute,
    delay = 120,
    onError = () => {},
    keyFor = (value) => value
  ) {
    this.#execute = execute;
    this.#delay = delay;
    this.#onError = onError;
    this.#keyFor = keyFor;
  }

  request(value, immediate = false) {
    const key = this.#keyFor(value);
    if (!this.#latest || this.#latest.key !== key) {
      this.#latest = { key, value, version: ++this.#version };
      this.#pending = this.#latest;
    }
    this.#immediate = immediate;
    if (immediate) {
      clearTimeout(this.#timer);
      this.#timer = null;
    }
    this.#schedule();
  }

  cancel() {
    this.#version++;
    this.#latest = null;
    this.#pending = null;
    clearTimeout(this.#timer);
    this.#timer = null;
  }

  #schedule() {
    if (this.#running || this.#timer || !this.#pending) {
      return;
    }
    if (this.#immediate) {
      this.#flush();
    } else {
      const remaining = Math.max(
        0,
        this.#delay - (Date.now() - this.#lastStarted)
      );
      this.#timer = setTimeout(() => this.#flush(), remaining);
    }
  }

  async #flush() {
    this.#timer = null;
    const request = this.#pending;
    if (!request) {
      return;
    }
    this.#pending = null;
    this.#running = true;
    this.#lastStarted = Date.now();
    try {
      const result = await this.#execute(
        request.value,
        () => request.version === this.#version
      );
      if (result === false && this.#latest === request) {
        this.#latest = null;
      }
    } catch (error) {
      if (this.#latest === request) {
        this.#latest = null;
      }
      this.#onError(error);
    } finally {
      this.#running = false;
      this.#schedule();
    }
  }
}
