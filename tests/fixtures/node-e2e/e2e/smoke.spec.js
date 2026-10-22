import { expect, test } from "@playwright/test";

// node-ci e2e with e2e-system-deps: when-missing: the browser starts without apt
test("renders a page", async ({ page }) => {
  await page.setContent("<h1>e2e fixture</h1>");
  await expect(page.locator("h1")).toHaveText("e2e fixture");
});
