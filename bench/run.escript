#!/usr/bin/env escript
%%! -pa _build/default/lib/erlang_base62/ebin

%% Microbenchmark for `base62'. Run directly via:
%%
%%     ./bench/run.escript
%%
%% or with explicit paths:
%%
%%     escript bench/run.escript

main(_) ->
    base62_bench:run().
