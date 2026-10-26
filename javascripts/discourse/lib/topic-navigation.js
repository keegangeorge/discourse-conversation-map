export async function navigateToPost(request, adapter, isCurrent) {
  if (!isCurrent()) {
    return false;
  }
  const window = adapter.isLoaded(request.number)
    ? null
    : await adapter.load(request.number);
  if (!isCurrent()) {
    return false;
  }
  // Committing the window and jumping are synchronous. A cancelled request must
  // not touch the live stream, even if its response arrives after a newer action.
  if (window) {
    adapter.commit(window);
  }
  adapter.jump(request.number, request.offset);
  return true;
}
