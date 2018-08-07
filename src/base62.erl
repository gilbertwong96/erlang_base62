-module(base62).

%% API exports
-export([encode/1,
         encode/2,
         decode/1,
         decode/2]).

%%====================================================================
%% API functions
%%====================================================================

%% note:
%%   encode original binary to base 62 string binary
%%   decode base 62 string or binary to base 62 string binary
%% description:
%%  use 6 bit as a group , the last 3 bit use 9 as prefix flag
%%  0~60: One Character from "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz012345678"
%%  61  : 9A
%%  62  : 9B
%%  63  : 9C


%% @doc Encode any data to base62 binary
-spec encode(string()
             | integer()
             | binary()) -> float().
encode(I) when is_integer(I) ->
    encode(integer_to_binary(I));
encode(S) when is_list(S)->
    encode(list_to_binary(S));
encode(B) when is_binary(B) ->
    encode(B, <<>>).

%% encode(D, string) ->
%%     binary_to_list(encode(D)).

%% @doc Decode base62 binary to origin data binary
decode(L) when is_list(L) ->
    decode(list_to_binary(L));
decode(B) when is_binary(B) ->
    decode(B, <<>>).



%%====================================================================
%% Internal functions
%%====================================================================

encode(D, string) ->
    binary_to_list(encode(D));
encode(<<Index1:6, Index2:6, Index3:6, Index4:6, Rest/binary>>, Acc) ->
    CharList = [encode_char(Index1), encode_char(Index2), encode_char(Index3), encode_char(Index4)],
    NewAcc = <<Acc/binary,(iolist_to_binary(CharList))/binary>>,
    encode(Rest, NewAcc);
encode(<<Index1:6, Index2:6, Index3:4>>, Acc) ->
    CharList = [encode_char(Index1), encode_char(Index2), encode_char(Index3)],
    NewAcc = <<Acc/binary,(iolist_to_binary(CharList))/binary>>,
    encode(<<>>, NewAcc);
encode(<<Index1:6, Index2:2>>, Acc) ->
    CharList = [encode_char(Index1), encode_char(Index2)],
    NewAcc = <<Acc/binary,(iolist_to_binary(CharList))/binary>>,
    encode(<<>>, NewAcc);
encode(<<>>, Acc) ->
    Acc.

decode(D, integer) ->
    binary_to_integer(decode(D));
decode(D, string) ->
    binary_to_list(decode(D));
decode(<<Head:8, Rest/binary>>, Acc)
  when bit_size(Rest) >= 8->
    case Head == $9 of
        true ->
            <<Head1:8, Rest1/binary>> = Rest,
            DecodeChar = decode_char(9, Head1),
            <<_:2, RestBit:6>> = <<DecodeChar>>,
            NewAcc = <<Acc/bitstring, RestBit:6>>,
            decode(Rest1, NewAcc);
        false ->
            DecodeChar = decode_char(Head),
            <<_:2, RestBit:6>> = <<DecodeChar>>,
            NewAcc = <<Acc/bitstring, RestBit:6>>,
            decode(Rest, NewAcc)
    end;
decode(<<Head:8, Rest/binary>>, Acc) ->
    DecodeChar = decode_char(Head),
    LeftBitSize = bit_size(Acc) rem 8,
    RightBitSize = 8 - LeftBitSize,
    <<_:LeftBitSize, RestBit:RightBitSize>> = <<DecodeChar>>,
    NewAcc = <<Acc/bitstring, RestBit:RightBitSize>>,
    decode(Rest, NewAcc);
decode(<<>>, Acc) ->
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
decode_char(I) when I >= $0 andalso I =< $8->
    I + 52 - $0;
decode_char(I) when I >= $A andalso I =< $Z->
    I - $A.

decode_char(9, I) ->
    I + 61 - $A.
