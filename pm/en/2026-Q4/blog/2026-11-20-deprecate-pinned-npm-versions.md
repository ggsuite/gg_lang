<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Deprecate pinnedNpmVersions

## Motivation

- `pinnedNpmVersions` listed the npm packages gg held at a fixed version
  during a dependency upgrade — `typescript: 6`
- gg no longer holds any npm package at a fixed version: whether an
  upgrade crosses major versions is decided per repository, for every
  package alike
- The constant has no reader anymore and its documentation described a
  behavior that no longer exists

## Strategy

- Deprecate the constant instead of removing it: removing a public member
  is a breaking change and would force every dependent to raise its
  constraint
- Keep `pinCommand`: holding a package at a version is a general
  operation of a package manager and stays available
- Add the missing `index.jsonc`

## Implementation

- `pinnedNpmVersions` carries `@Deprecated` and a one-line doc comment;
  it is removed with the next breaking release
- The test of its value is removed
- The doc comment of `pinCommand` no longer talks about a pin that re-runs
  on every upgrade
- `index.jsonc` describes the scope of the repo and the APIs each
  dependent uses

## Open Points

- Remove `pinnedNpmVersions` with the next breaking release
