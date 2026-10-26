export default class ScrubQueue {
  #execute;
  #delay;
  #onError;
  #pending = null;
  #running = false;
  #timer = null;
  #version = 0;
  #immediate = false;

  constructor(execute, delay = 120, onError = () => {}) {
    this.#execute = execute;
    this.#delay = delay;
    this.#onError = onError;
  }

  request(value, immediate = false) {
    this.#pending = { value, version: ++this.#version };
    this.#immediate = immediate;
    if (immediate) {
      clearTimeout(this.#timer);
      this.#timer = null;
    }
    this.#schedule();
  }

  cancel() {
    this.#version++;
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
      this.#timer = setTimeout(() => this.#flush(), this.#delay);
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
    try {
      await this.#execute(
        request.value,
        () => request.version === this.#version
      );
    } catch (error) {
      this.#onError(error);
    } finally {
      this.#running = false;
      this.#schedule();
    }
  }
}
