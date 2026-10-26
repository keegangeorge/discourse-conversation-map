let session = null;

export function mapSession(topicId, lastReadId) {
  if (session?.topicId !== topicId) {
    session = { topicId, lastReadId, anchor: null };
  }
  return session;
}

export function resetMapSessionForUrl(url) {
  const match = url.match(/\/t\/([^/?#]+)(?:\/(\d+))?/);
  const topicId = match
    ? Number(/^\d+$/.test(match[1]) ? match[1] : match[2])
    : null;
  if (session?.topicId !== topicId) {
    session = null;
  }
}
