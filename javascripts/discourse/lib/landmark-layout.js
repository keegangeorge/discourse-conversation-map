// Keep direct actions disjoint without moving the map's proportional anchors.
// Dense maps scroll the action column rather than shrinking or hiding buttons.
export function layoutLandmarks(marks, height, streamLength) {
  const contentHeight = Math.max(height, marks.length * 28 + 8, 32);
  const centers = marks.map((mark) =>
    Math.max(
      16,
      Math.min(
        contentHeight - 16,
        (mark.index / Math.max(1, streamLength - 1)) * height
      )
    )
  );
  for (let index = 1; index < centers.length; index++) {
    centers[index] = Math.max(centers[index], centers[index - 1] + 28);
  }
  if (centers.length) {
    centers[centers.length - 1] = Math.min(
      centers[centers.length - 1],
      contentHeight - 16
    );
    for (let index = centers.length - 2; index >= 0; index--) {
      centers[index] = Math.min(centers[index], centers[index + 1] - 28);
    }
  }
  return { contentHeight, centers };
}
