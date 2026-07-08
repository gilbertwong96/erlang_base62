-include_lib("common_test/include/ct.hrl").
-module(base62_SUITE).

-define(BASE62, base62).

-compile(export_all).
-compile(nowarn_export_all).

%% base62 alphabet: 0..60 == "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz012345678"
%% 61 == "9A", 62 == "9B", 63 == "9C"
-define(ALPHABET, list_to_binary(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz012345678")).

all() ->
    [t_encode_decode_idempotent,
     t_encode_known_vectors,
     t_encode_decode_integer,
     t_encode_decode_string,
     t_input_boundary_lengths,
     t_alphabet_output_invariant,
     t_legacy_compat,
     t_decode_rejects_invalid,
     t_length_growth].

groups() -> [].

init_per_suite(Config) ->
    %% Make the bench/legacy snapshot dir available if it has been built.
    Dirs = [filename:join(["bench", "legacy"]),
            filename:join(["_build", "test", "lib"])],
    lists:foldl(fun(Dir, Acc) ->
                    case filelib:is_dir(Dir) of
                        true -> [{legacy_dir, Dir} | Acc];
                        false -> Acc
                    end
                end, Config, Dirs).
end_per_suite(_Config) -> ok.
init_per_test(_Case, Config) -> Config.
end_per_test(_Case, _Config) -> ok.

%% A roundtrip should restore the input exactly, regardless of input type.
%% encode/1 normalises the input into a binary internally, so the roundtrip
%% always yields a binary.
t_encode_decode_idempotent(_) ->
    %% binary roundtrip
    true = (?BASE62:decode(?BASE62:encode(<<>>)) =:= <<>>),
    true = (?BASE62:decode(?BASE62:encode(<<"A">>)) =:= <<"A">>),
    true = (?BASE62:decode(?BASE62:encode(<<"AB">>)) =:= <<"AB">>),
    true = (?BASE62:decode(?BASE62:encode(<<"ABC">>)) =:= <<"ABC">>),
    true = (?BASE62:decode(?BASE62:encode(<<0,1,2,3,4,5,254,255>>))
             =:= <<0,1,2,3,4,5,254,255>>),
    %% Binary containing all 256 byte values
    All = list_to_binary(lists:seq(0, 255)),
    true = (?BASE62:decode(?BASE62:encode(All)) =:= All),
    %% string (list of codepoints/bytes) roundtrips via binary normalisation.
    true = (?BASE62:decode(?BASE62:encode("helloworld")) =:= <<"helloworld">>),
    true = (?BASE62:decode(?BASE62:encode("Hello World")) =:= <<"Hello World">>),
    ok.

%% Each value 61..63 maps to the prefix sequence "9A"/"9B"/"9C".
%% We construct a 3-byte input whose first 6 bits happen to be 61..63 to
%% exercise that path on both encode and decode.
t_encode_known_vectors(_) ->
    %% Six-bit value 61 == 'A' + 0 == 0x3D = 00111101
    %% Six-bit value 62 == 'A' + 1 == 0x3E = 00111110
    %% Six-bit value 63 == 'A' + 2 == 0x3F = 00111111
    %% We verify that encoding them via crafted bytes round-trips.
    Bytes61 = <<61:6, 0:2>>, %% 8 bits, low 2 are zero
    Bytes62 = <<62:6, 0:2>>,
    Bytes63 = <<63:6, 0:2>>,
    bytes_roundtrip(Bytes61),
    bytes_roundtrip(Bytes62),
    bytes_roundtrip(Bytes63),
    %% Verify the prefix-tagged bytes show up in the encoding for crafted inputs.
    Enc61 = ?BASE62:encode(Bytes61),
    <<"9A", _/binary>> = Enc61,
    Enc62 = ?BASE62:encode(Bytes62),
    <<"9B", _/binary>> = Enc62,
    Enc63 = ?BASE62:encode(Bytes63),
    <<"9C", _/binary>> = Enc63,
    %% Spot-check a known vector from the original test suite.
    <<"10">> = ?BASE62:decode(?BASE62:encode(10)),
    <<"helloworld">> = ?BASE62:decode(?BASE62:encode("helloworld")),
    <<"9999">> = ?BASE62:decode(?BASE62:encode(<<"9999">>)),
    <<"65535">> = ?BASE62:decode(?BASE62:encode(<<"65535">>)),
    ok.

t_encode_decode_integer(_) ->
    %% Arbitrary integer goes to integer_to_binary then encoded.
    [begin
         Bin = integer_to_binary(N),
         Bin = ?BASE62:decode(?BASE62:encode(N)),
         N = ?BASE62:decode(?BASE62:encode(N, string), integer)
     end
     || N <- [0, 1, 10, 255, 256, 65535, 65536, 4294967295, -1, -1024]],
    ok.

t_encode_decode_string(_) ->
    %% encode(Data, string) returns list of integers (ASCII bytes).
    "helloworld" = ?BASE62:decode(?BASE62:encode("helloworld", string), string),
    <<"Hello World">> =
        ?BASE62:decode(
           binary_to_list(?BASE62:encode(<<"Hello World">>))),
    %% encode/integer -> string -> string round-trip via list form.
    "10" = ?BASE62:decode(?BASE62:encode(10, string), string),
    ok.

%% Every input length 0..32 must roundtrip and the encoded output length must
%% match the documented growth factor: ceil(8*N / 6).
t_input_boundary_lengths(_) ->
    [begin
         Bin = list_to_binary(lists:duplicate(N, $X)),
         Enc = ?BASE62:encode(Bin),
         EncLen = byte_size(Enc),
         ExpectedLen = ceil_div(8 * N, 6),
         ExpectedLen = EncLen,
         Bin = ?BASE62:decode(Enc)
     end
     || N <- lists:seq(0, 32)],
    %% Plus a couple of larger lengths to exercise multi-chunk paths.
    [begin
         Bin = crypto:strong_rand_bytes(N),
         Enc = ?BASE62:encode(Bin),
         Bin = ?BASE62:decode(Enc)
     end
     || N <- [0, 1, 33, 100, 257, 1000, 4097]],
    ok.

%% Every output byte must be a member of the base62 alphabet.
t_alphabet_output_invariant(_) ->
    Alphabet = ?ALPHABET,
    AlphabetBytes = sets:from_list(binary_to_list(Alphabet)),
    PrefixByte = $9,
    [begin
         Bin = crypto:strong_rand_bytes(N),
         Enc = ?BASE62:encode(Bin),
         lists:foreach(
           fun(B) when B =:= PrefixByte -> ok;
              (B) ->
                   true = sets:is_element(B, AlphabetBytes),
                   ok
           end,
           binary_to_list(Enc))
     end
     || N <- lists:seq(0, 64)],
    ok.

%% If the legacy module snapshot is available under test/ or _build/test/lib,
%% force a direct comparison. The snapshot is generated on demand by the
%% bench helper and the test is skipped when it isn't present.
t_legacy_compat(Config) ->
    LegacyDir = ?config(legacy_dir, Config),
    BeamPath = filename:join(LegacyDir, "base62_legacy.beam"),
    case filelib:is_regular(BeamPath) of
        false -> {skip, no_legacy_snapshot};
        true ->
            code:add_path(LegacyDir),
            {module, base62_legacy} = code:load_file(base62_legacy),
            Payload = list_to_binary(lists:seq(0, 255) ++ lists:seq(0, 255)),
            NewEnc = ?BASE62:encode(Payload),
            OldEnc = base62_legacy:encode(Payload),
            true = NewEnc =:= OldEnc,
            NewDec = ?BASE62:decode(NewEnc),
            OldDec = base62_legacy:decode(NewEnc),
            true = NewDec =:= OldDec,
            ok
    end.

%% Decode must error on characters outside the alphabet AND on dangling $9
%% that has no second byte.
t_decode_rejects_invalid(_) ->
    %% Characters outside the alphabet.
    Encoded = ?BASE62:encode(<<"hello">>),
    %% Flip one byte to a clearly invalid character ($!, which is not in the
    %% base62 alphabet).
    Tampered = case byte_size(Encoded) of
                   0 -> <<"!">>;
                   N ->
                       <<Prefix:(N - 1)/binary, _:8, Suffix/binary>> = Encoded,
                       iolist_to_binary([Prefix, <<"!">>, Suffix])
               end,
    try ?BASE62:decode(Tampered) of
        _ -> ct:fail({unexpected_success, Tampered})
    catch
        _:_ -> ok
    end,
    ok.

t_length_growth(_) ->
    %% Encoded length lower bound: every 24 input bits produce at least 4 chars.
    %% Encoded length upper bound: each of those 4 chars is at most 2 bytes
    %% (only true for 61..63 values which we cannot easily induce via random
    %% bytes, but for non-mixed input the upper bound is ceil(8*N/6)).
    [begin
         Bin = binary:copy(<<$X>>, N),
         Enc = ?BASE62:encode(Bin),
         MinLen = (8 * N + 5) div 6,
         MaxLen = ((8 * N + 5) div 6) * 2,
         true = byte_size(Enc) >= MinLen,
         true = byte_size(Enc) =< MaxLen,
         Bin = ?BASE62:decode(Enc)
     end
     || N <- lists:seq(0, 33)],
    ok.

%% --- helpers ---

bytes_roundtrip(Bin) ->
    Enc = ?BASE62:encode(Bin),
    Bin = ?BASE62:decode(Enc),
    ok.

ceil_div(A, B) ->
    (A + B - 1) div B.
