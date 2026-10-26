export default class PreviewLoader {
  #load;
  #onBatch;
  #waiting = new Map();
  #pending = new Set();
  #priority = new Set();
  #active = null;
  #generation = 0;

  constructor(load, onBatch = () => {}) {
    this.#load = load;
    this.#onBatch = onBatch;
  }

  load(ids, { priority = false } = {}) {
    if (priority) {
      ids.forEach((id) => {
        if (!this.#waiting.has(id) || this.#pending.has(id)) {
          this.#priority.add(id);
        }
      });
    }
    const promises = ids.map((id) => {
      if (this.#waiting.has(id)) {
        return this.#waiting.get(id).promise;
      }
      let resolve;
      let reject;
      const promise = new Promise((yes, no) => {
        resolve = yes;
        reject = no;
      });
      this.#waiting.set(id, { promise, resolve, reject });
      this.#pending.add(id);
      return promise;
    });
    while (this.#pending.size > 32) {
      const oldest =
        [...this.#pending].find((id) => !this.#priority.has(id)) ??
        this.#pending.values().next().value;
      this.#priority.delete(oldest);
      this.#pending.delete(oldest);
      this.#waiting.get(oldest).resolve(null);
      this.#waiting.delete(oldest);
    }
    this.#drain();
    return Promise.all(promises);
  }

  cancel() {
    this.#generation++;
    this.#pending.clear();
    this.#priority.clear();
    for (const item of this.#waiting.values()) {
      item.resolve(null);
    }
    this.#waiting.clear();
    this.#active?.abort?.();
  }

  async #drain() {
    if (this.#active || !this.#pending.size) {
      return;
    }
    const generation = this.#generation;
    const ids = [...this.#pending]
      .sort(
        (a, b) => Number(this.#priority.has(b)) - Number(this.#priority.has(a))
      )
      .slice(0, 20);
    ids.forEach((id) => {
      this.#pending.delete(id);
      this.#priority.delete(id);
    });
    let active;
    try {
      active = this.#load(ids);
    } catch (error) {
      for (const id of ids) {
        this.#waiting.get(id)?.reject(error);
        this.#waiting.delete(id);
      }
      this.#drain();
      return;
    }
    this.#active = active;
    try {
      const posts = await active;
      if (generation === this.#generation) {
        this.#onBatch(posts);
        const byId = new Map(posts.map((post) => [post.id, post]));
        for (const id of ids) {
          this.#waiting.get(id)?.resolve(byId.get(id) || null);
          this.#waiting.delete(id);
        }
      }
    } catch (error) {
      if (generation === this.#generation) {
        for (const id of ids) {
          this.#waiting.get(id)?.reject(error);
          this.#waiting.delete(id);
        }
      }
    } finally {
      this.#active = null;
      this.#drain();
    }
  }
}
