# Changelog

<!-- %% CHANGELOG_ENTRIES %% -->

## 0.4.0 - 2026-11-20

This release follows the JSON→URL specification for percent encoding, so
encoded values are safe to drop into a URL query. URLs encoded by 0.4.0 use a
different form from 0.3.0; decode URLs stored from 0.2.0 or 0.3.0 with
`JsonUrl.decode(url, legacy: true)`.

### Added

- `JsonUrl.decode/2` takes a `legacy: true` option that decodes URLs
  produced by json_url 0.2.0 and 0.3.0 back to the values they encoded.

### Changed

- Require Elixir 1.18 or later.
- Escape only strings that would otherwise decode as a number or keyword,
  so `"16 Pro"` encodes as `16+Pro` rather than `!16+Pro`. This matches the
  JSON→URL reference implementation, but json_url 0.3.0 and earlier can't
  decode the new form.
- **Breaking:** follow the JSON→URL address-bar friendly syntax for percent
  encoding. `encode/1` percent-encodes anything that isn't safe in a URL
  query, so `"A&B=C"` becomes `A%26B%3DC` and no longer splits into two
  query parameters. `decode/1` decodes percent-encoded text and rejects
  malformed percent-encoding, invalid UTF-8, and a raw `&`, `=` or control
  character. Pass `legacy: true` to decode URLs stored from 0.2.0 or 0.3.0.

### Fixed

- Decode numbers with fractions or exponents (`1.25`, `1e+2`) as floats
  instead of failing.
- Read numbers and `true`/`false`/`null` only when they make up the whole
  token, so `16+Pro`, `false-positive` and `001` decode as strings. A float
  too large to represent is an error.
- Return an error for objects that contain bare values and arrays that
  contain key-value pairs, instead of raising or returning tuples.

## 0.3.0 - 13 Jul 2024

- Support utf-8 strings

## 0.2.0 - 30 Apr 2024

- Breaking change: The empty string decodes to "!e" and "e" is otherwise
  not escaped.

## 0.1.2 - 14 Mar 2024

- Fix missing typespec on `decode/1`.

## 0.1.1 - 14 Mar 2024

- Fix format of changelog

## 0.1.0 - 14 Mar 2024

- Initial revision
