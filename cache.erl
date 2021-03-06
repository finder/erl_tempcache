-module(cache).
-behaviour(gen_server).
-export([start_link/2, set/3, set/2, get/1, add/3, add/2, del/1, start/0, start_shell/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([timeout_to_secs/1]).


rpc(Msg) ->
    gen_server:call({global, erl_tempcache}, Msg, 2000).

set(Key, Val, Timeout) -> 
    rpc({set, Key, Val, Timeout}).

set(Key, Val) ->
    set(Key, Val, 0).

get(Key) ->
    rpc({get, Key}).

add(Key, Val, Timeout) ->
    rpc({add, Key, Val, Timeout}).

add(Key, Val) ->
    add(Key, Val, 0).

del(Key)->
    rpc({del, Key}).

start() ->
    cache_sup:start_link().

start_shell() ->
    cache_sup:start_link(shell).

start_link(Tab, Internal) -> 
    gen_server:start_link({global, erl_tempcache}, ?MODULE, [Tab, Internal], []).

init([Tab, Internal])->
    {ok, {Tab, Internal}}.

timeout_to_secs(Timeout) ->
    {Mega, Sec, _} = now(),
    Mega*1000000 + Sec + Timeout.

is_valid_key(Key, Internal) ->
    A = ets:lookup(Internal, Key),
    case A of 
        [] -> 
            false;
        [H|_] ->
            {_, {Timeout, _, _}} = H,
            Now = timeout_to_secs(0),
            if 
                Timeout =:= 0 ->
                    true;
                Timeout < Now ->
                    false;
                true ->
                    true
            end
    end.

get_key(Key, Tab) ->
    %todo: increase Get
    A = ets:lookup(Tab, Key),
    case A of
        [] ->
            none;
        [X|_] ->
            {_, Val} = X,
            Val
    end.

make_timeout(Timeout) ->
    case Timeout of 
        0 ->
            0;
        X ->
            timeout_to_secs(X)
    end.
%% this function handles the msg call and does the work.
handler({set, Key, Value, Timeout}, From, {Tab, Internal}) ->
    Timeout2 = make_timeout(Timeout),    
    ets:insert(Tab, {Key, Value}),
    ets:insert(Internal, {Key, {Timeout2, 0, timeout_to_secs(0)}}),
    cache_free:check_table(),
    gen_server:reply(From, ok);

handler({get, Key}, From, {Tab, Internal}) ->
    Reply = case is_valid_key(Key, Internal) of 
        true ->
            case get_key(Key, Tab) of
                none ->
                    none;
                Val ->
                    {ok, Val}
            end;
        false ->
            none
        end,

    gen_server:reply(From, Reply);

handler({add, Key, Value, Timeout}, From, {Tab, Internal}) ->
    Reply = case is_valid_key(Key, Internal) of 
        true ->
            {error, exists};
        false ->
            Timeout2 = make_timeout(Timeout),
            ets:insert(Tab, {Key, Value}),
            ets:insert(Internal, {Key, {Timeout2, 0, timeout_to_secs(0)}}),
            cache_free:check_table(),
            ok
        end,

    gen_server:reply(From,Reply);

handler({del, Key}, From, {Tab, Internal}) ->
    ets:delete(Tab, Key),
    ets:delete(Internal, Key),
    gen_server:reply(From, ok);

handler(Other, From, {_State}) ->
    gen_server:reply(From, {error, invalid_call, Other}).

handle_call(Msg, From, State) ->  
    %% Launch a process and return the pid
    spawn(fun() -> handler(Msg, From, State) end),
    {noreply, State}.

handle_cast(_ , State) ->  {noreply, State}.
handle_info(_, State) -> {noreply, State}.
terminate(_Reason, _State) -> ok.
code_change(_Oldversion, State, _Extra) -> {ok, State}.

