%% Frozen copy of the *original* `base62' implementation before OTP-style
%% optimisation. Captured here so benchmarks and the legacy_compat CT case
%% can guard against any unintended behavioural drift in future versions.
%%
%% DO NOT EDIT — regenerate via bench/snapshot.sh when intentionally
%% rebasing on a new pre-optimisation baseline.

-module(base62_legacy).

-export([legacy_encode/1, legacy_decode/1]).

legacy_encode(I) when is_integer(I) ->
    enc_loop(integer_to_binary(I), <<>>);
legacy_encode(S) when is_list(S) ->
    enc_loop(list_to_binary(S), <<>>);
legacy_encode(B) when is_binary(B) ->
    enc_loop(B, <<>>).

legacy_decode(L) when is_list(L) ->
    dec_loop(list_to_binary(L), <<>>);
legacy_decode(B) when is_binary(B) ->
    dec_loop(B, <<>>).

%% --- Original internal helpers (frozen) ---------------------------------

enc_loop(<<Index1:6, Index2:6, Index3:6, Index4:6, Rest/binary>>, Acc) ->
    CharList = [encode_char(Index1), encode_char(Index2),
                encode_char(Index3), encode_char(Index4)],
    NewAcc = <<Acc/binary, (iolist_to_binary(CharList))/binary>>,
    enc_loop(Rest, NewAcc);
enc_loop(<<Index1:6, Index2:6, Index3:4>>, Acc) ->
    CharList = [encode_char(Index1), encode_char(Index2), encode_char(Index3)],
    NewAcc = <<Acc/binary, (iolist_to_binary(CharList))/binary>>,
    enc_loop(<<>>, NewAcc);
enc_loop(<<Index1:6, Index2:2>>, Acc) ->
    CharList = [encode_char(Index1), encode_char(Index2)],
    NewAcc = <<Acc/binary, (iolist_to_binary(CharList))/binary>>,
    enc_loop(<<>>, NewAcc);
enc_loop(<<>>, Acc) ->
    Acc.

dec_loop(<<Head:8, Rest/binary>>, Acc) when bit_size(Rest) >= 8 ->
    case Head == $9 of
        true ->
            <<Head1:8, Rest1/binary>> = Rest,
            DecodeChar = decode_char(9, Head1),
            <<_:2, RestBit:6>> = <<DecodeChar>>,
            NewAcc = <<Acc/bitstring, RestBit:6>>,
            dec_loop(Rest1, NewAcc);
        false ->
            DecodeChar = decode_char(Head),
            <<_:2, RestBit:6>> = <<DecodeChar>>,
            NewAcc = <<Acc/bitstring, RestBit:6>>,
            dec_loop(Rest, NewAcc)
    end;
dec_loop(<<Head:8, Rest/binary>>, Acc) ->
    DecodeChar = decode_char(Head),
    LeftBitSize = bit_size(Acc) rem 8,
    RightBitSize = 8 - LeftBitSize,
    <<_:LeftBitSize, RestBit:RightBitSize>> = <<DecodeChar>>,
    NewAcc = <<Acc/bitstring, RestBit:RightBitSize>>,
    dec_loop(Rest, NewAcc);
dec_loop(<<>>, Acc) ->
    Acc.

encode_char(I) when I < 26 ->
    $A + I;
encode_char(I) when I < 52 ->
    $a + I - 26;
encode_char(I) when I < 61 ->
    $0 + I - 52;
encode_char(I) ->
    [$9, $A + I - 61].

decode_char(I) when I >= $a andalso I =< $z ->
    I + 26 - $a;
decode_char(I) when I >= $0 andalso I =< $8 ->
    I + 52 - $0;
decode_char(I) when I >= $A andalso I =< $Z ->
    I - $A.

decode_char(9, I) ->
    I + 61 - $A.
