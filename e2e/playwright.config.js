import { defineConfig, devices } from "@playwright/test";

// The target is production, so there is no server to start and no fixture data
// to seed. Point SITE_URL elsewhere to run the same specs against a preview.
export default defineConfig({
  testDir: ".",
  use: {
    baseURL: process.env.SITE_URL ?? "https://christiansantiago.dev",
    trace: "on-first-retry",
  },
  // CloudFront serves a deploy from hundreds of edges and does not finish
  // invalidating them all at once, so a first failure here is not yet news.
  retries: process.env.CI ? 2 : 0,
  reporter: process.env.CI ? "github" : "list",
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
