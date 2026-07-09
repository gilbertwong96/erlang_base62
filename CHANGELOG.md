# Changelog

All notable changes to `erlang_base62` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-07-09

### Requirements

- **Minimum OTP version: 27**. The `-moduledoc`/`-doc` markdown
  attribute syntax (EEP-48 doc chunks) and `stdlib/base64`-style
  bit-syntax helpers are only available from OTP 27 onward.

### Changed

- **Encoder rewrite**: hot path now processes 3 input bytes per iteration
  (24 bits → 4 base62 chars), matching `stdlib/base64`'s natural
  alignment. Dropped the per-iteration `iolist_to_binary/1` allocation
  in favour of a direct bit-syntax accumulator.
- **Encoder helpers**: `b62e/1` is a per-value clause table mapping
  0..60 to a single byte and 61..63 to the two-byte prefix pair
  `[$9, $A|B|C]`. Marked `-compile({inline, [b62e/1]})` so the BEAM
  substitutes the body at each call site.
- **Decoder rewrite**: 4-byte bulk clause dispatches `b62d/1` on
  four bytes in parallel and writes `V1:6, V2:6, V3:6, V4:6` into
  the accumulator in one bit-syntax expression. The `$9` prefix
  handler consumes the following byte to recover the high 6-bit
  values 61..63.
- **Decoder helpers**: `b62d/1` collapsed to three range guards
  (uppercase, lowercase, digits before `$9`) plus the `$9` prefix
  and out-of-alphabet bytes as sentinels. Marked
  `-compile({inline, [b62d/1]})`.
- **Documentation**: replaced Edoc-style `@doc`/`@moduledoc` with
  OTP 27+ `-doc`/`-moduledoc` markdown attributes, rendered through
  `rebar3_ex_doc`.

### Performance

- Encode: **2.6–2.8× faster** than the 1.0.x baseline.
- Decode: **1.9–2.3× faster** than the 1.0.x baseline.
- See [BENCHMARK.md](BENCHMARK.md) for the full A/B table across
  payload sizes (64 B, 1 KB, 16 KB, 64 KB) and operations (encode,
  decode) on Apple M1 Pro / OTP 29.

### Added

- `bench/base62_bench.erl` — torque-style A/B benchmark module
  producing an aligned markdown report with ips, mean, median, p99,
  and memory columns.
- `bench/legacy/base62_legacy.erl` — frozen pre-optimization
  snapshot used as the A/B baseline.
- `justfile` with `bench`, `bench-compare`, `test`, `build`,
  `docs`, and `clean` recipes.
- `BENCHMARK.md` — full A/B benchmark results.
- `.github/workflows/ci.yml` — runs `rebar3 ct`, generates a
  Cobertura coverage report via `covertool`, and uploads to Codecov.
- `test/prop_base62.erl` + `test/prop_base62_SUITE.erl` — 200
  shrink-driven PropEr properties (roundtrip, alphabet, encode
  alignment, etc.).

### Fixed

- Bulk decoder trailing-byte handling: the last 6-bit value in the
  encoded stream is stored as a partial slice (only as many bits as
  needed to fill the trailing 8-bit byte, with leading zeros). The
  bulk path now routes the trailing byte through `finalize_tail_only/2`
  to pick the correct slice, matching the legacy decoder's bit-for-bit
  output. (Previously the bulk path emitted `V:6` for the last value
  and `finalize_tail` truncated the wrong bits, silently dropping
  bytes from large payloads.)
- Removed the dead `Need =:= 0` clause in `finalize_tail_only/2`
  flagged by `rebar3 dialyzer`.
- `t_legacy_compat` now compiles the legacy snapshot on demand from
  `init_per_suite` and no longer gets skipped after `just clean`.

[1.1.0]: https://github.com/gilbertwong96/erlang_base62/compare/1.0.1...v1.1.0

## [1.0.1] - 2022-11-07

Last release of the pre-optimization implementation. The wire format
and public API are unchanged from 1.0.0; the 1.1.0 rewrite is
byte-identical to this baseline for all test inputs (verified by
`t_legacy_compat` and 200 PropEr properties).

[1.0.1]: https://github.com/gilbertwong96/erlang_base62/releases/tag/1.0.1
