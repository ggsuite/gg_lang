# sample_project_ts

A minimal TypeScript project fixture used to validate the gg toolchain's
language-universal behaviour (project-type detection, manifest reads, and the
catalog-driven analyze/format/test/publish commands) against realistic
`package.json` / `tsconfig.json` / `vitest` / `eslint` files.

Unit tests read these files directly (no Node toolchain required). The
`vitest`/`eslint`/`tsc` tooling is only exercised by Node-gated integration
tests.
