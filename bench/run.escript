#!/usr/bin/env escript
%%! -pa _build/bench/lib/erlang_base62/ebin

%% Microbenchmark for the current `base62' only (no legacy A/B).
%%
%%     just bench

main(_) ->
    base62_bench:run().
