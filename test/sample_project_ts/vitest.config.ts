import { defineConfig } from 'vitest/config';

// The coverage gate is expressed here so `gg_test` only needs to fail when
// vitest fails (thresholds are enforced by vitest itself).
export default defineConfig({
  test: {
    coverage: {
      provider: 'v8',
      thresholds: {
        lines: 100,
        functions: 100,
        branches: 100,
        statements: 100,
      },
    },
  },
});
