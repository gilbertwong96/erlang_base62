# justfile for erlang_base62
#
# Run `just` (no args) to list available recipes.

set dotenv-load := false
set shell := ["bash", "-uc"]

# Default: list available recipes.
default:
    @just --list

# Compile the project (and its test profile) without running tests.
build:
    rebar3 compile

# Run the full Common Test suite (CT + PropEr).
test:
    rebar3 ct

# Run the microbenchmark (new only), without the legacy A/B rows.
bench: _build-bench-module
    escript bench/run.escript

# Run the A/B microbenchmark comparing the current `base62` module
# against the frozen `bench/legacy/base62_legacy` snapshot. Compiles
# the legacy beam on demand.
bench-compare: _build-bench-module
    @if [ ! -f bench/legacy/base62_legacy.beam ]; then \
        erlc -o bench/legacy bench/legacy/base62_legacy.erl; \
    fi
    escript bench/run_compare.escript

# Build edoc HTML documentation.
docs:
    rebar3 edoc

# Remove build artifacts.
clean:
    rebar3 clean

# Internal: compile the bench module into the bench profile's ebin so
# the bench escripts (which load from _build/bench/...) can find it.
_build-bench-module:
    rebar3 as bench compile
    erlc -o _build/bench/lib/erlang_base62/ebin bench/base62_bench.erl
