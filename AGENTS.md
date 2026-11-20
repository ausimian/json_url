# json_url

Elixir library for encoding and decoding [JSON→URL](https://github.com/jsonurl/specification)
text. Published to hex.pm as `json_url`.

## Layout

- `lib/json_url.ex`: the whole public API (`encode/1`, `decode/1`). The
  parser is built with `nimble_parsec`.
- `test/json_url_test.exs`: example tests plus `stream_data` property tests
  (round-trip encode/decode).

## Development

- Elixir `~> 1.18`. CI tests 1.18 / OTP 27, 1.19.5 / OTP 28.3 and the
  latest stable Elixir / OTP.
- Run `mix precommit` before every commit. It runs compile with warnings
  as errors, `deps.unlock --unused`, `format`, `credo --strict` and `test`.
  Don't run the checks one at a time.
- Note each user-visible change in `RELEASE.md` on the feature branch,
  under Keep a Changelog headings (`### Added`, `### Changed`, `### Fixed`, ...).

## Releasing

- `@version` in `mix.exs` is the single source of truth.
- Cut a release with `mix publisho <patch|minor|major>`. It bumps
  `@version`, moves `RELEASE.md` into `CHANGELOG.md`, commits and tags.
  Then run `git push && git push --tags`.
- Tags are bare semver (`0.4.0`, not `v0.4.0`). Pushing a tag publishes
  to hex.pm through `.github/workflows/publish-to-hex.yml`.
