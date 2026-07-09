# erlang_base62

A small, fast Base62 codec for Erlang. Accepts binaries, strings (lists of
bytes), and integers as inputs; bin round-trips through itself, and other
inputs are normalised to a binary internally.

## Build

```
$ make
```

## Simple Usage

### encode

``` erlang
<<"MTA">> = base62:encode(10),
base62:encode(<<"10">>),
base62:encode("10").
```

### decode
``` erlang
%% decode data to specified format , default format is binary
base62:decode(<<"MTA">>),
base62:decode("MTA"),
base62:decode(<<"MTA">>,string).
base62:decode("MTA",string).
```

## Benchmarks

See [BENCHMARK.md](BENCHMARK.md) for full results. Summary: the
optimized implementation is **2.6–2.8× faster** at encoding and
**1.9–2.3× faster** at decoding compared to the legacy baseline.

## Development

Common tasks are wrapped as [`just`](https://github.com/casey/just) recipes.
Run `just` (no args) to list them.

```sh
just build           # rebar3 compile
just test            # rebar3 ct (CT + PropEr)
just bench           # microbenchmark the current `base62` module
just bench-compare   # A/B against the frozen `bench/legacy` snapshot
just docs            # rebar3 edoc
just clean           # remove _build/ and the legacy beam
```
