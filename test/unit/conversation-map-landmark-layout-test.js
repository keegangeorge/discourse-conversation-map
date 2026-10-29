import { module, test } from "qunit";
import { layoutLandmarks } from "../../javascripts/discourse/lib/landmark-layout.js";

module("Unit | Conversation Map | landmark layout", function () {
  test("clustered and endpoint actions stay disjoint and contained", function (assert) {
    for (const height of [0, 60, 280, 600]) {
      const marks = [0, 1, 2, 98, 99].map((index) => ({ index }));
      const { centers, contentHeight } = layoutLandmarks(marks, height, 100);
      assert.true(centers[0] >= 16, "first target has room for its outline");
      assert.true(
        centers.at(-1) <= contentHeight - 16,
        "last target is contained"
      );
      for (let index = 1; index < centers.length; index++) {
        assert.true(
          centers[index] - centers[index - 1] >= 28,
          "24px actions have a gap"
        );
      }
    }
  });

  test("dense maps scroll rather than shrinking targets", function (assert) {
    const marks = Array.from({ length: 32 }, (_, index) => ({ index }));
    const { centers, contentHeight } = layoutLandmarks(marks, 200, 32);
    assert.true(contentHeight > 200);
    assert.strictEqual(centers.length, 32);
    assert.deepEqual(layoutLandmarks([], 200, 0), {
      contentHeight: 200,
      centers: [],
    });
  });
});
