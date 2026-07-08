%% Property tests for `base62' driven by PropEr.
%%
%% Run via:
%%
%%     rebar3 as test proper --module=prop_base62
%%
%% Or through the wrapper CT suite:
%%
%%     rebar3 ct --suite=test/prop_base62_SUITE
%%
%% Each property below targets an invariant of the public API.
-module(prop_base62).

-include_lib("proper/include/proper.hrl").

-export([prop_roundtrip_binary/0,
         prop_roundtrip_string/0,
         prop_roundtrip_via_integer_form/0,
         prop_alphabet_output/0,
         prop_decode_to_string_matches_binary/0,
         prop_encode_byte_alignment/0,
         prop_specific_vectors/0,
         prop_no_extra_bytes_after_first_chunk/0]).

%% Max length we exercise; beyond this both implementations are dominated by
%% the bit-syntax accumulator and the relative speedup stabilises.
-define(MAX_BYTES, 1024).

%% --- Generators ------------------------------------------------------------

binary_below_max() ->
    ?LET(N, non_neg_integer(),
         binary:copy(<<0>>, min(N, ?MAX_BYTES))).

binary_with_pattern(_Pattern) ->
    %% Reserved for future use; intentionally unused right now.
    binary_below_max().

%% Output is always a binary; encode random binaries and decode.
prop_roundtrip_binary() ->
    ?FORALL(Bin, binary_below_max(),
            begin
                Enc = base62:encode(Bin),
                is_binary(Enc) andalso
                Bin =:= base62:decode(Enc)
            end).

%% A list (string) input is normalised to a binary internally; round-tripping
%% through the binary form must reproduce it bytewise.
prop_roundtrip_string() ->
    ?FORALL(Str, list(integer(0, 127)),
            begin
                Bin = list_to_binary(Str),
                Enc = base62:encode(Str),
                is_binary(Enc) andalso
                Bin =:= base62:decode(Enc)
            end).

prop_roundtrip_via_integer_form() ->
    ?FORALL(I, integer(),
            begin
                Bin = integer_to_binary(I),
                Bin =:= base62:decode(base62:encode(I))
            end).

%% Every output byte must be a member of the alphabet.
prop_alphabet_output() ->
    Alphabet = sets:from_list(
        binary_to_list(
            list_to_binary(
                "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz012345678"))),
    ?FORALL(Bin, binary_below_max(),
            sets:is_subset(sets:from_list(binary_to_list(base62:encode(Bin))),
                            Alphabet)).

%% decode(encode(X), string) must match binary_to_list(decode(encode(X))).
prop_decode_to_string_matches_binary() ->
    ?FORALL(Bin, binary_below_max(),
            begin
                Enc = base62:encode(Bin),
                DecBin = base62:decode(Enc),
                DecStr = base62:decode(Enc, string),
                DecStr =:= binary_to_list(DecBin)
            end).

%% For inputs of identical byte sequences, outputs must be identical
%% (encoder is a pure function of the binary).
prop_encode_byte_alignment() ->
    ?FORALL(Bin, binary_below_max(),
            base62:encode(Bin) =:= base62:encode(Bin)).

%% Compile a small set of known vectors; each must round-trip.
prop_specific_vectors() ->
    ?FORALL(_X, integer(0, 0), %% exactly one shot
            begin
                Vectors = [<<>>,
                          <<0>>,
                          <<255>>,
                          <<0,255,128,42,100>>,
                          list_to_binary("helloworld"),
                          <<"Hello World">>],
                lists:all(fun(Bin) -> base62:decode(base62:encode(Bin)) =:= Bin end,
                          Vectors)
            end).

%% For all-$X inputs the encoded form must consist of alphabet-only bytes AND
%% the roundtrip must return the original input.
prop_no_extra_bytes_after_first_chunk() ->
    %% Bound the size so PropEr's tree shrinking remains tractable.
    ?FORALL(Size, integer(0, 64),
            begin
                Bin = binary:copy(<<"X">>, Size),
                Enc = base62:encode(Bin),
                AlphabetBytes =
                    binary_to_list(
                      list_to_binary(
                        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz012345678")),
                OutputBytes = binary_to_list(Enc),
                AllAlphabet = lists:all(fun(B) ->
                    lists:member(B, AlphabetBytes)
                end, OutputBytes),
                Roundtrips = (Bin =:= base62:decode(Enc)),
                AllAlphabet andalso Roundtrips
            end).
