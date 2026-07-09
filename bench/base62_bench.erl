%% Microbenchmark for `base62'. Produces an aligned markdown report with
%% per-iteration statistics (ips, mean, median, p99) and memory per
%% operation.
%%
%%   just bench          — current `base62' only
%%   just bench-compare  — A/B against the frozen `bench/legacy' snapshot

-module(base62_bench).

-compile(export_all).
-compile(nowarn_export_all).

-define(Sizes, [64, 1024, 16#4000, 16#10000]).
-define(WarmupMs, 200).
-define(RunMs, 1000).
-define(MaxSamples, 100000).

%% ---- entry points -----------------------------------------------------

%% Benchmark the current `base62' module only (no legacy rows).
run() ->
    report(false).

%% A/B benchmark: current `base62' vs. the frozen `base62_legacy'.
run_compare() ->
    report(true).

report(Legacy) ->
    io:format("~n## Benchmarks~n"),
    print_env(),
    HasLegacy = Legacy andalso (code:ensure_loaded(base62_legacy) =:= {module, base62_legacy}),
    case {Legacy, HasLegacy} of
        {true, false} ->
            io:format("~n> `base62_legacy' not loaded — A/B rows omitted.~n"
                      "> Build `bench/legacy/base62_legacy.beam' to include legacy.~n");
        _ -> ok
    end,
    lists:foreach(fun(N) -> run_size(N, HasLegacy) end, ?Sizes),
    io:format("~nRun benchmarks locally:~n~n"
              "    just bench~n"
              "    just bench-compare~n", []).

print_env() ->
    io:format("~n~s, OTP ~s.~n",
              [cpu_name(), erlang:system_info(otp_release)]).

%% ---- per-size runner --------------------------------------------------

run_size(N, Legacy) ->
    Payload = fixed_payload(N),
    NewEnc  = base62:encode(Payload),
    LegEnc  = case Legacy of
                  true  -> base62_legacy:legacy_encode(Payload);
                  false -> NewEnc
              end,
    SizeLabel = format_size(N),
    EncRows = [{<<"base62">>,  fun() -> base62:encode(Payload) end, byte_size(NewEnc)}
               | case Legacy of
                     true  -> [{<<"legacy">>, fun() -> base62_legacy:legacy_encode(Payload) end, byte_size(LegEnc)}];
                     false -> []
                 end],
    print_table("Encode (" ++ SizeLabel ++ ")", EncRows),
    DecRows = [{<<"base62">>,  fun() -> base62:decode(NewEnc) end, byte_size(Payload)}
               | case Legacy of
                     true  -> [{<<"legacy">>, fun() -> base62_legacy:legacy_decode(LegEnc) end, byte_size(Payload)}];
                     false -> []
                 end],
    print_table("Decode (" ++ SizeLabel ++ ")", DecRows).

%% ---- table printer (column-aligned markdown) -------------------------

print_table(Title, Rows) ->
    io:format("~n### ~s~n~n", [Title]),
    Stats = [bench_row(Name, Fun, Mem) || {Name, Fun, Mem} <- Rows],
    {_, BestIdx} = best_index(Stats),
    Headers = ["Library", "ips", "mean", "median", "p99", "memory"],
    Rows0 = [Headers | [format_row(Name, S, Idx =:= BestIdx) || {Idx, {Name, S}} <- indexed(Stats)]],
    Widths = column_widths(Rows0),
    print_aligned(Widths, Rows0).

indexed(List) ->
    {_, Indexed} = lists:foldl(fun(E, {I, Acc}) -> {I + 1, [{I, E} | Acc]} end, {0, []}, List),
    lists:reverse(Indexed).

format_row(Name, {Ips, Mean, Median, P99, Mem}, Bold) ->
    B = case Bold of true -> "**"; false -> "" end,
    [[B, Name, B],
     [B, format_ips(Ips), B],
     [B, format_time(Mean), B],
     [B, format_time(Median), B],
     [B, format_time(P99), B],
     [B, format_bytes(Mem), B]].

column_widths(Rows) ->
    lists:foldl(
      fun(Row, Acc) ->
              lists:zipwith(fun(Cell, W) -> max(str_width(Cell), W) end,
                           Row, Acc)
      end, [0, 0, 0, 0, 0, 0], Rows).

print_aligned(Widths, [Header | Rows]) ->
    print_row(Widths, Header),
    print_sep(Widths),
    lists:foreach(fun(R) -> print_row(Widths, R) end, Rows).

print_row(Widths, Row) ->
    Cells = lists:zipwith(
              fun(W, Cell) ->
                      S = to_list(Cell),
                      string:left(S, W)
              end, Widths, Row),
    io:format("| ~ts |~n", [string:join(Cells, " | ")]).

print_sep(Widths) ->
    Cells = [lists:duplicate(W + 2, $-) || W <- Widths],
    io:format("|~ts|~n", [string:join(Cells, "|")]).

%% Visible width of a string (counts characters, not bytes).
%% Handles iolists containing binaries by deep-flattening to charlist.
str_width(B) when is_binary(B) -> length(unicode:characters_to_list(B));
str_width(L) when is_list(L) ->
    length(deep_flatten(L));
str_width(C) when is_integer(C) -> 1.

deep_flatten(B) when is_binary(B) -> unicode:characters_to_list(B);
deep_flatten(L) when is_list(L) -> lists:append([deep_flatten(X) || X <- L]);
deep_flatten(C) when is_integer(C) -> [C].

best_index(Stats) ->
    {BestIps, BestIdx} =
        lists:foldl(
          fun({_, {Ips, _, _, _, _}}, {Best, Idx}) when Ips > Best ->
                  {Ips, Idx};
             (_, Acc) -> Acc
          end, {-1, 0}, Stats),
    {BestIps, BestIdx}.

%% ---- per-row benchmark ------------------------------------------------

bench_row(Name, Fun, MemHint) ->
    _ = timed_loop(Fun, ?WarmupMs),
    Samples = collect_samples(Fun, ?RunMs),
    Sorted  = lists:sort(Samples),
    Len     = length(Sorted),
    Total   = lists:sum(Samples),
    Mean    = Total / max(Len, 1),
    Median  = percentile(Sorted, 50),
    P99     = percentile(Sorted, 99),
    Ips     = (Len * 1_000_000_000) / max(Total, 1),
    Mem     = measure_memory(Fun, MemHint),
    {Name, {Ips, Mean, Median, P99, Mem}}.

%% ---- statistics helpers ----------------------------------------------

collect_samples(Fun, RunMs) ->
    collect_samples(Fun, erlang:monotonic_time(nanosecond),
                    RunMs * 1_000_000, []).

collect_samples(Fun, Start, BudgetNs, Acc) ->
    T0 = erlang:monotonic_time(nanosecond),
    Fun(),
    T1 = erlang:monotonic_time(nanosecond),
    case (length(Acc) >= ?MaxSamples) orelse
         (T1 - Start >= BudgetNs) of
        true ->
            lists:reverse([T1 - T0 | Acc]);
        false ->
            collect_samples(Fun, Start, BudgetNs, [T1 - T0 | Acc])
    end.

percentile(Sorted, Pct) when is_list(Sorted) ->
    Len = length(Sorted),
    Idx = max(1, min(Len, round(Len * Pct / 100))),
    lists:nth(Idx, Sorted).

%% ---- memory measurement ----------------------------------------------
%% Returns the memory (in bytes) consumed by the result of `Fun'.
%% For binaries (the common case for encode/decode) we use `byte_size'
%% directly; for other terms we fall back to `erts_debug:flat_size'.
measure_memory(Fun, _Fallback) ->
    Result = Fun(),
    case is_binary(Result) of
        true  -> byte_size(Result);
        false -> erts_debug:flat_size(Result) * erlang:system_info(wordsize)
    end.

%% ---- formatting -------------------------------------------------------

format_ips(Ips) when Ips >= 1_000_000 -> lists:flatten(io_lib:format("~.1fM", [Ips / 1_000_000]));
format_ips(Ips) when Ips >= 1_000     -> lists:flatten(io_lib:format("~.1fK", [Ips / 1_000]));
format_ips(Ips)                       -> lists:flatten(io_lib:format("~.1f", [Ips])).

format_time(Ns) when Ns >= 1_000_000 -> lists:flatten(io_lib:format("~.2f ms", [Ns / 1_000_000]));
format_time(Ns) when Ns >= 1_000     -> lists:flatten(io_lib:format("~.2f μs", [Ns / 1_000]));
format_time(Ns)                      -> lists:flatten(io_lib:format("~.2f ns", [Ns / 1])).

format_bytes(B) when B >= 1024 -> lists:flatten(io_lib:format("~.2f KB", [B / 1024]));
format_bytes(B)                 -> lists:flatten(io_lib:format("~w B", [B])).

format_size(N) when N >= 1024 -> lists:flatten(io_lib:format("~w KB", [N div 1024]));
format_size(N)                 -> lists:flatten(io_lib:format("~w B", [N])).

%% ---- helpers ----------------------------------------------------------

to_list(B) when is_binary(B) -> unicode:characters_to_list(B);
to_list(L) when is_list(L)  -> deep_flatten(L);
to_list(C) when is_integer(C) -> [C].

timed_loop(Fun, MinMs) ->
    Start = erlang:monotonic_time(microsecond),
    loop_until(Fun, Start, MinMs * 1000, 0).

loop_until(Fun, Start, MinUs, N) ->
    Fun(),
    case erlang:monotonic_time(microsecond) - Start >= MinUs of
        true  -> N + 1;
        false -> loop_until(Fun, Start, MinUs, N + 1)
    end.

fixed_payload(0) -> <<>>;
fixed_payload(N) -> crypto:strong_rand_bytes(N).

cpu_name() ->
    Raw = os:cmd("sysctl -n machdep.cpu.brand_string 2>/dev/null || "
                 "cat /proc/cpuinfo 2>/dev/null | grep 'model name' | "
                 "head -1 | cut -d: -f2 | xargs || echo 'Unknown'"),
    string:trim(Raw, trailing, "\n").
