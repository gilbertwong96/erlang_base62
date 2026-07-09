#!/usr/bin/env escript
%%! -pa _build/bench/lib/erlang_base62/ebin -pa bench/legacy

%% A/B microbenchmark: current `base62' vs. frozen legacy snapshot.
%%
%%     just bench-compare

main(_) ->
    base62_bench:run_compare().
