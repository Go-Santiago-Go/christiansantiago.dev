import { expect, test } from "@playwright/test";

test("the footer reports a visit count", async ({ page }) => {
  await page.goto("/");

  // Asserted on shape rather than value: this very load increments the count,
  // so any exact number is stale before the assertion runs. The em dash the
  // markup ships with fails this, which is what makes a dead counter visible.
  await expect(page.locator("#visitor-count")).toHaveText(/^[\d,]+$/);
});
