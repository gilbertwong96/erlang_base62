%% Common Test wrapper that runs every property in `prop_base62'. Skipped
%% silently if PropEr is not on the path.
-module(prop_base62_SUITE).

-include_lib("proper/include/proper.hrl").

-compile(export_all).
-compile(nowarn_export_all).

-define(PROPS,
        [prop_roundtrip_binary,
         prop_roundtrip_string,
         prop_roundtrip_via_integer_form,
         prop_alphabet_output,
         prop_decode_to_string_matches_binary,
         prop_encode_byte_alignment,
         prop_specific_vectors,
         prop_no_extra_bytes_after_first_chunk]).

all() -> [t_run_properties].

init_per_suite(Config) ->
    case code:which(proper) of
        non_existing -> {skip, "PropEr not available; tests skipped"};
        _ -> Config
    end.

end_per_suite(_Config) -> ok.
init_per_test(_Case, Config) -> Config.
end_per_test(_Case, _Config) -> ok.

t_run_properties(Config) ->
    case code:which(proper) of
        non_existing -> {skip, "PropEr not available"};
        _ ->
            NumTests = proplists:get_value(numtests, Config, 200),
            io:format("Running PropEr with numtests=~p~n", [NumTests]),
            Passed =
                lists:foldl(
                  fun(PropName, Acc) ->
                      PropFun = prop_base62:PropName(),
                      io:format("--- running ~p ---~n", [PropName]),
                      Result = proper:quickcheck(PropFun,
                                                 [NumTests, {to_file, user}]),
                      io:format("~p => ~p~n", [PropName, Result]),
                      Acc andalso Result =:= true
                  end,
                  true,
                  ?PROPS),
            case Passed of
                true -> ok;
                false ->
                    ct:fail({propEr_failed, ?PROPS})
            end
    end.
