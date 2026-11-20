### Changed

- Require Elixir 1.18 or later.

### Fixed

- Decode numbers with fractions or exponents (`1.25`, `1e+2`) as floats
  instead of failing.
- Read numbers and `true`/`false`/`null` only when they make up the whole
  token, so `16+Pro`, `false-positive` and `001` decode as strings. A float
  too large to represent is an error.
- Return an error for objects that contain bare values and arrays that
  contain key-value pairs, instead of raising or returning tuples.
