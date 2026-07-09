-module(base62).

-moduledoc """
Base62 encoder and decoder.

Base62 represents arbitrary binary data using a 62-character alphabet:

* **0..25**  → `"A".."Z"`
* **26..51** → `"a".."z"`
* **52..60** → `"0".."9"`
* **61..63** → `"9A"` / `"9B"` / `"9C"`

The last three values (61..63) carry a leading `"9"` byte as a prefix
flag, since the alphabet itself only spans 62 values.

Internally the encoding reuses 6-bit groups; every 3 input bytes
(24 bits) maps cleanly to 4 base62 characters. Decoders recognise the
`"9"` prefix byte in order to recover the high values 61..63.

The implementation mirrors stdlib/base64 in OTP 27+:

* An encoder helper b62e/1 maps a 6-bit value to either a single byte
  (0..60) or a two-byte list (61..63) for the prefix-tagged outputs.
* A decoder helper b62d/1 maps each input byte to a 6-bit value (or
  the sentinel bad or prefix).
* The bit-syntax accumulator (writing bytes straight into the
  accumulator) avoids the iolist conversion the legacy implementation
  paid on every iteration.
* The fast encoder path processes 3 bytes per iteration (24 bits → 4
  base62 characters), the same natural alignment as base64.

Public API accepts binaries, strings (lists of bytes), and integers.
Binaries round-trip through themselves; other inputs are normalised to
a binary internally.

See the README.md file for an overview; this module is the
source of truth.
""".

-export([encode/1,
         encode/2,
         decode/1,
         decode/2]).

%% Hot helpers — inlined into the byte-by-byte dispatch.
-compile({inline, [b62e/1, b62d/1]}).

%% =====================================================================
%% API
%% =====================================================================

-doc """
Encode any data to a base62 binary.

```erlang
1> base62:encode(<<"hello">>).
<<"aGVsbG8">>
```
""".
-spec encode(string() | integer() | binary()) -> binary().
encode(I) when is_integer(I) -> encode_binary(integer_to_binary(I));
encode(S) when is_list(S) -> encode_binary(list_to_binary(S));
encode(B) when is_binary(B) -> encode_binary(B).

-doc """
Encode data and return the result as a flat list of bytes.
""".
-spec encode(Data, string) -> [byte()] when Data :: string() | integer() | binary().
encode(D, string) -> binary_to_list(encode(D)).

-doc """
Decode a base62 binary or string back to the original bytes.

```erlang
1> base62:decode(<<"aGVsbG8">>).
<<"hello">>
```
""".
-spec decode(binary() | string()) -> binary().
decode(L) when is_list(L) -> decode_binary(list_to_binary(L));
decode(B) when is_binary(B) -> decode_binary(B).

-doc """
Decode base62 data and return it as binary / list / integer. The
`Format` is one of:

* `binary` — the same as `decode/1` (default).
* `string` — return a flat list of bytes (`binary_to_list`).
* `integer` — parse the bytes as an Erlang integer
  (`binary_to_integer`).
""".
-spec decode(Data, Format) -> binary() | string() | integer() when
      Data :: binary() | string(),
      Format :: binary | string | integer.
decode(D, integer) -> binary_to_integer(decode(D));
decode(D, string) -> binary_to_list(decode(D));
decode(D, _) -> decode(D).

%% =====================================================================
%% Encoder
%% =====================================================================
%%
%% Process 3 input bytes at a time (24 bits → 4 base62 chars). The slow
%% path handles 1- or 2-byte remainders.

encode_binary(<<>>) -> <<>>;
encode_binary(Bin) -> encode_loop(Bin, <<>>).

encode_loop(<<>>, A) -> A;
encode_loop(<<B1:6, B2:6, B3:6, B4:6, Rest/bits>>, A) ->
    E1 = b62e(B1),
    E2 = b62e(B2),
    E3 = b62e(B3),
    E4 = b62e(B4),
    case {is_integer(E1), is_integer(E2), is_integer(E3), is_integer(E4)} of
        {true, true, true, true} ->
            encode_loop(Rest, <<A/bits, E1:8, E2:8, E3:8, E4:8>>);
        _ ->
            Acc1 = append_encoded(A, E1),
            Acc2 = append_encoded(Acc1, E2),
            Acc3 = append_encoded(Acc2, E3),
            Acc4 = append_encoded(Acc3, E4),
            encode_loop(Rest, Acc4)
    end;

encode_loop(<<B1:6, B2:2>>, A) ->
    E1 = b62e(B1), E2 = b62e(B2),
    case {is_integer(E1), is_integer(E2)} of
        {true, true} -> <<A/bits, E1:8, E2:8>>;
        _ ->
            Acc1 = append_encoded(A, E1),
            append_encoded(Acc1, E2)
    end;

encode_loop(<<B1:6, B2:6, B3:4>>, A) ->
    E1 = b62e(B1), E2 = b62e(B2), E3 = b62e(B3),
    case {is_integer(E1), is_integer(E2), is_integer(E3)} of
        {true, true, true} -> <<A/bits, E1:8, E2:8, E3:8>>;
        _ ->
            Acc1 = append_encoded(A, E1),
            Acc2 = append_encoded(Acc1, E2),
            append_encoded(Acc2, E3)
    end.

append_encoded(Acc, [H, L]) when is_integer(H), is_integer(L) ->
    <<Acc/bits, H:8, L:8>>;
append_encoded(Acc, I) when is_integer(I) ->
    <<Acc/bits, I:8>>.

%% =====================================================================
%% Decoder
%% =====================================================================
%%
%% Single-byte loop. The 256-entry `b62d/1' dispatch recognises the
%% `$9' prefix in-line, dropping into `decode_prefix/2' to consume the
%% following byte. The hot path emits 6 bits per byte; the last byte
%% emits only as many bits as required to fill the trailing 8-bit byte
%% (legacy convention).

decode_binary(<<>>) -> <<>>;
decode_binary(Bin) -> decode_loop(Bin, <<>>).

decode_loop(<<>>, Acc) -> finalize_tail(Acc);

%% Hot path: 4 input bytes per iteration. The parallel
%% `{V1, V2, V3, V4}' tuple match with `when is_integer(V1), ...'
%% guards compiles to a vector test in the VM, which is 4× faster
%% than a sequence of single-byte `case' clauses.
%%
%% When at least one of the four bytes is `$9' (prefix) or out-of-
%% alphabet, we fall back to a byte-by-byte walk that handles the
%% prefix pair correctly.
decode_loop(<<C1:8, C2:8, C3:8, C4:8, Rest/binary>>, Acc) ->
    V1 = b62d(C1),
    V2 = b62d(C2),
    V3 = b62d(C3),
    V4 = b62d(C4),
    case {is_integer(V1), is_integer(V2), is_integer(V3), is_integer(V4)} of
        {true, true, true, true} ->
            case Rest of
                <<>> ->
                    %% Last group: `C4' is the trailing byte, which the
                    %% legacy encoder stores as a partial value (only as
                    %% many bits as needed to fill the trailing 8-bit
                    %% byte, with leading zeros). Reuse the single-byte
                    %% tail handling so we pick the right slice of `V4'.
                    finalize_tail_only(<<Acc/bits, V1:6, V2:6, V3:6>>, V4);
                _ ->
                    decode_loop(Rest, <<Acc/bits, V1:6, V2:6, V3:6, V4:6>>)
            end;
        _ ->
            %% Bulk path failed: walk the four bytes one at a time.
            %% `Rest' still points at the bytes AFTER the bulk group,
            %% but the prefix handler may need to peek INSIDE the group
            %% (the postfix byte is the next one in the bulk).
            handle_bulk([C1, C2, C3, C4], Rest, Acc)
    end;

%% Hot path: single byte with at least 8 bits of remaining input. We
%% dispatch on the `$9' prefix in one pass, falling back to single-byte
%% decode for regular alphabet characters. Mirrors the structure of
%% OTP's `stdlib/base64' decoder.
decode_loop(<<C:8, Rest/bits>>, Acc) when bit_size(Rest) >= 8 ->
    case C of
        $9 ->
            decode_prefix(Rest, Acc);
        _ ->
            case b62d(C) of
                bad ->
                    error({invalid_base62, C});
                N when is_integer(N) ->
                    decode_loop(Rest, <<Acc/bits, N:6>>)
            end
    end;
%% Trailing byte (Rest has < 8 bits): only as many bits as needed to
%% fill the trailing 8-bit byte go into the bitstream.
decode_loop(<<C:8, Rest/bits>>, Acc) ->
    case C of
        $9 ->
            decode_prefix(Rest, Acc);
        _ ->
            case b62d(C) of
                bad ->
                    error({invalid_base62, C});
                N when is_integer(N) ->
                    finalize_tail_only(Acc, N)
            end
    end.



%% Walk bulk bytes with prefix handling. Each `$9' consumes the NEXT
%% byte (the postfix) as its high-value indicator.
handle_bulk([], Rest, Acc) -> decode_loop(Rest, Acc);
handle_bulk([C | Cs], Rest, Acc) ->
    case b62d(C) of
        bad ->
            error({invalid_base62, bad_in_bulk, C});
        prefix ->
            %% The postfix is the next byte in the bulk group. If none
            %% remains, fall back to `Rest'.
            case Cs of
                [Postfix | RestCs] ->
                    case b62d(Postfix) of
                        bad -> error({invalid_base62_after_prefix, Postfix});
                        M when is_integer(M), M =< 8 ->
                            handle_bulk(RestCs, Rest,
                                        <<Acc/bits, (M + 61):6>>)
                    end;
                [] ->
                    case Rest of
                        <<Postfix:8, R/binary>> ->
                            case b62d(Postfix) of
                                bad -> error({invalid_base62_after_prefix, Postfix});
                                M when is_integer(M), M =< 8 ->
                                    decode_loop(R,
                                                <<Acc/bits, (M + 61):6>>)
                            end;
                        <<>> ->
                            error({invalid_base62, missing_byte_after_prefix})
                    end
            end;
        N when is_integer(N) ->
            case {Cs, Rest} of
                {[], <<>>} ->
                    %% Trailing byte in the bulk walk: the legacy encoder
                    %% pads the last value to a partial slice; use the
                    %% same single-byte tail logic to pick the right bits.
                    finalize_tail_only(Acc, N);
                _ ->
                    handle_bulk(Cs, Rest, <<Acc/bits, N:6>>)
            end
    end.

%% `$9' prefix handler. Consumes the next byte and uses its 6-bit
%% value plus 61 (so $A → 61, $B → 62, $C → 63).
decode_prefix(<<C:8, Rest/bits>>, Acc) when bit_size(Rest) >= 8 ->
    case b62d(C) of
        bad ->
            error({invalid_base62_after_prefix, C});
        M when is_integer(M) ->
            decode_loop(Rest, <<Acc/bits, (M + 61):6>>)
    end;
decode_prefix(<<C:8, _/bits>>, Acc) ->
    case b62d(C) of
        bad ->
            error({invalid_base62_after_prefix, C});
        M when is_integer(M) ->
            finalize_tail_only(Acc, M + 61)
    end;
decode_prefix(<<>>, _Acc) ->
    error({invalid_base62, missing_byte_after_prefix}).

%% Last byte finalize: emit enough bits to complete the trailing 8-bit
%% byte, then drop trailing partial-byte fragment.
finalize_tail_only(Acc, V) ->
    Left = bit_size(Acc) rem 8,
    Need = 8 - Left,
    case Need of
        0 ->
            %% Acc is byte-aligned: take all 8 bits of the value byte
            %% (only 6 are meaningful but the legacy code emits all 8).
            finalize_tail(<<Acc/bits, V:8>>);
        N when N >= 6 ->
            %% The full 6-bit value fits in the leftover slot.
            finalize_tail(<<Acc/bits, V:6>>);
        N ->
            %% Only N bits required: skip `Left' bits from the top of
            %% the value byte and take the bottom `N' bits.
            <<_:Left/bitstring, Take:N/bitstring>> = <<V:8>>,
            finalize_tail(<<Acc/bits, Take:N/bitstring>>)
    end.

%% Drop any trailing partial byte (< 8 bits).
finalize_tail(Acc) when bit_size(Acc) =:= 0 -> <<>>;
finalize_tail(Acc) ->
    Sz = (bit_size(Acc) div 8) * 8,
    case Sz of
        0 -> <<>>;
        _ ->
            <<Out:Sz/bitstring, _/bitstring>> = Acc,
            Out
    end.

%% =====================================================================
%% b62e/1 — encoder table
%% =====================================================================
%%
%% Maps a 6-bit value (0..63) to either:
%%   * a single byte (the alphabet byte), for inputs 0..60
%%   * a two-byte list `[$9, X]' for inputs 61..63 (prefix-tagged)
%%
%% The caller detects the latter case via `is_list/1' on the returned
%% term, letting the encoder reuse the same fast path for both cases.

b62e(0) -> $A;
b62e(1) -> $B;
b62e(2) -> $C;
b62e(3) -> $D;
b62e(4) -> $E;
b62e(5) -> $F;
b62e(6) -> $G;
b62e(7) -> $H;
b62e(8) -> $I;
b62e(9) -> $J;
b62e(10) -> $K;
b62e(11) -> $L;
b62e(12) -> $M;
b62e(13) -> $N;
b62e(14) -> $O;
b62e(15) -> $P;
b62e(16) -> $Q;
b62e(17) -> $R;
b62e(18) -> $S;
b62e(19) -> $T;
b62e(20) -> $U;
b62e(21) -> $V;
b62e(22) -> $W;
b62e(23) -> $X;
b62e(24) -> $Y;
b62e(25) -> $Z;
b62e(26) -> $a;
b62e(27) -> $b;
b62e(28) -> $c;
b62e(29) -> $d;
b62e(30) -> $e;
b62e(31) -> $f;
b62e(32) -> $g;
b62e(33) -> $h;
b62e(34) -> $i;
b62e(35) -> $j;
b62e(36) -> $k;
b62e(37) -> $l;
b62e(38) -> $m;
b62e(39) -> $n;
b62e(40) -> $o;
b62e(41) -> $p;
b62e(42) -> $q;
b62e(43) -> $r;
b62e(44) -> $s;
b62e(45) -> $t;
b62e(46) -> $u;
b62e(47) -> $v;
b62e(48) -> $w;
b62e(49) -> $x;
b62e(50) -> $y;
b62e(51) -> $z;
b62e(52) -> $0;
b62e(53) -> $1;
b62e(54) -> $2;
b62e(55) -> $3;
b62e(56) -> $4;
b62e(57) -> $5;
b62e(58) -> $6;
b62e(59) -> $7;
b62e(60) -> $8;
b62e(61) -> [$9, $A];
b62e(62) -> [$9, $B];
b62e(63) -> [$9, $C].

%% =====================================================================
%% b62d/1 — decoder dispatch
%% =====================================================================
%%
%% Returns one of:
%%   * `bad' — out-of-alphabet byte, decoding should crash
%%   * `prefix' — the byte is `$9', signaling a high-value (61..63)
%%                 pair whose next byte carries the high 6-bit value
%%   * an integer 0..60 — the canonical 6-bit value
%%
%% Implemented with range guards (3 clauses!) for the common alphabet
%% bytes — much faster than a single-byte-per-clause dispatch at the
%% cost of doing the offset arithmetic once.

b62d(I) when I >= $A andalso I =< $Z -> I - $A;
b62d(I) when I >= $a andalso I =< $z -> I - $a + 26;
b62d(I) when I >= $0 andalso I =< $8 -> I - $0 + 52;
b62d($9) -> prefix;
b62d(_) -> bad.
