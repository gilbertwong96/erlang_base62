# base62


**Build**

```
$ make
```

** Simple Usage **

encode
``` erlang
<<"MTA">> = base62:encode(10),
base62:encode(<<"10">>),
base62:encode("10").
```
decode
``` erlang
%% decode data to specified format , default foramt is binary
base62:decode(<<"MTA">>),
base62:decode("MTA"),
base62:decode(<<"MTA">>,string).
base62:decode("MTA",string).
```
