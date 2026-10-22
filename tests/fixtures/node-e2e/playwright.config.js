import { defineConfig } from "@playwright/test";

export default defineConfig({ testDir: "e2e", reporter: process.env.CI ? "github" : "list" });
