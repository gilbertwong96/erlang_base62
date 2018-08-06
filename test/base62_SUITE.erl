-module(base62_SUITE).

-define(BASE62, base62).

-compile(export_all).
-compile(nowarn_export_all).

all() -> [t_base62_encode].

t_base62_encode(_) ->
    <<"10">> = ?BASE62:decode(?BASE62:encode(10)),
    <<"helloworld">> = ?BASE62:decode(?BASE62:encode("helloworld")),
    <<"Hello World">> = ?BASE62:decode(
                           binary_to_list(
                             ?BASE62:encode(<<"Hello World">>))
                          ),
    <<"9999">> = ?BASE62:decode(?BASE62:encode(<<"9999">>)),
    <<"65535">> = ?BASE62:decode(?BASE62:encode(<<"65535">>)).
