%% Microbenchmark for `base62'. Runs the encoder and decoder on a small
%% set of fixed payload sizes and prints throughput in bytes/second.
%%
%% Run via:
%%
%%     rebar3 shell --eval 'base62_bench:run().' --eval 'init:stop().'
%%
%% For a real A/B comparison against a saved legacy snapshot, place
%% `base62_legacy.beam' under bench/legacy/ first; the test harness in
%% `base62_SUITE: t_legacy_compat' reads it back automatically.

-module(base62_bench).

-compile(export_all).
-compile(nowarn_export_all).

-define(Sizes, [64, 1024, 16#4000, 16#10000]).
-define(WarmupMs, 200).
-define(RunMs, 1000).

run() ->
    io:format("~n=== base62 microbenchmark ===~n"),
    io:format("~18s ~18s ~18s~n",
              ["bytes", "enc bytes/s", "dec bytes/s"]),
    lists:foreach(fun run_for_size/1, ?Sizes),
    io:format("=== done ===~n").

run_for_size(N) ->
    Payload = fixed_payload(N),
    Encoded = base62:encode(Payload),
    E = time_runner(N, fun() -> base62:encode(Payload) end),
    D = time_runner(N, fun() -> base62:decode(Encoded) end),
    io:format("~18w ~18w ~18w~n", [N, E, D]).

%% Time `Fun' until at least RunMs have elapsed. Returns bytes/second.
%% `PayloadBytes' is the per-call input size used for the throughput calculation.
time_runner(PayloadBytes, Fun) ->
    %% Warmup
    _ = timed_run(Fun, ?WarmupMs),
    {Micros, Iters} = timed_run(Fun, ?RunMs),
    Bytes = Iters * PayloadBytes,
    (Bytes * 1_000_000) div max(Micros, 1).

timed_run(Fun, MinMs) ->
    Start = erlang:monotonic_time(microsecond),
    Iters = loop_until(Fun, Start, MinMs * 1000, 0),
    {erlang:monotonic_time(microsecond) - Start, Iters}.

loop_until(Fun, Start, MinUs, N) ->
    Fun(),
    Elapsed = erlang:monotonic_time(microsecond) - Start,
    case Elapsed >= MinUs of
        true -> N + 1;
        false -> loop_until(Fun, Start, MinUs, N + 1)
    end.

fixed_payload(N) when N =< 0 -> <<>>;
fixed_payload(N) -> crypto:strong_rand_bytes(N).
