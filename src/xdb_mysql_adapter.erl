%%%-------------------------------------------------------------------
%%% @doc
%%% MySQL Adapter.
%%% @end
%%%-------------------------------------------------------------------
-module(xdb_mysql_adapter).

-behaviour(xdb_adapter).
-behaviour(xdb_adapter_transaction).

%% Adapter callbacks
-export([
  child_spec/2,
  insert/4,
  insert_all/4,
  update/5,
  delete/4,
  execute/5
]).

-export([
  transaction/3,
  in_transaction/1,
  rollback/2
]).

%% Defaults
-define(DEFAULT_POOL_SIZE, erlang:system_info(schedulers_online)).
-define(AUTO_PK, [primary_key, autogenerate_id]).

%%%===================================================================
%%% Adapter callbacks
%%%===================================================================

%% @hidden
child_spec(Repo, Opts) ->
  Name = pool_name(Repo),
  PoolArgs = pool_args(Name, Opts),
  WorkersArgs = parse_opts([{repo, Repo} | Opts]),
  poolboy:child_spec(Name, PoolArgs, WorkersArgs).

% @TODO: add onconflict option
%% @hidden
insert(Repo, #{schema := Schema} = Meta, Fields0, _Opts) ->
  Fields = normalize(Schema, Fields0),
  case get(self()) of
    undefined ->
      poolboy:transaction(pool_name(Repo), fun(Worker) ->
        do_insert(Worker, Meta, Fields)
      end);
    Pid ->
      do_insert(Pid, Meta, Fields)
  end.

% @TODO: add onconflict option
%% @hidden
insert_all(Repo, #{schema := Schema} = Meta, List0, _Opts) ->
  List = [normalize(Schema, Fields) || Fields <- List0],
  case get(self()) of
    undefined ->
      poolboy:transaction(pool_name(Repo), fun(Worker) ->
        do_insert_all(Worker, Meta, List)
      end);
    Pid ->
      do_insert_all(Pid, Meta, List)
  end.

%% @hidden
update(Repo, #{schema := Schema, source := Source}, Fields, Filters, _Opts) ->
  Condition = transform(Filters),
  Query = #{where => Condition, updates => maps:to_list(normalize(Schema, Fields))},
  case get(self()) of
    undefined ->
      poolboy:transaction(pool_name(Repo), fun(Worker) ->
        do_update(Worker, Repo, Filters, Schema, Source, Query)
      end);
    Pid ->
      do_update(Pid, Repo, Filters, Schema, Source, Query)
  end.

%% @hidden
delete(Repo, #{schema := Schema, source := Source}, Filters, _Opts) ->
  Condition = transform(Filters),
  Query = #{where => Condition},
  case get(self()) of
    undefined ->
      poolboy:transaction(pool_name(Repo), fun(Worker) ->
        do_delete(Worker, Repo, Filters, Schema, Source, Query)
      end);
    Pid ->
      do_delete(Pid, Repo, Filters, Schema, Source, Query)
  end.

%% @hidden
execute(Repo, Op, #{schema := Schema, source := Source}, Query, _Opts) ->
  case get(self()) of
    undefined ->
      poolboy:transaction(pool_name(Repo), fun(Worker) ->
        do_execute(Worker, Op, Schema, Source, Query)
      end);
    Pid ->
      do_execute(Pid, Op, Schema, Source, Query)
  end.

%% @hidden
transaction(Repo, Fun, _Opts) ->
  TxFun =
    fun() ->
      case Fun() of
        {error, Reason} -> xdb_lib:raise(Reason);
        Ok              -> Ok
      end
    end,

  poolboy:transaction(pool_name(Repo), fun(Worker) ->
    _ = put(self(), Worker),
    Res =
      case mysql:transaction(Worker, TxFun) of
        {atomic, Result} ->
          {ok, Result};
        {aborted, {Error, Reason}} when is_list(Reason) ->
          {error, Error};
        {aborted, Reason} ->
          {error, Reason}
      end,
    _ = erase(self()),
    Res
  end).

%% @hidden
in_transaction(Repo) ->
  case get(self()) of
    undefined ->
      poolboy:transaction(pool_name(Repo), fun(Worker) ->
        mysql:in_transaction(Worker)
      end);
    Pid ->
      mysql:in_transaction(Pid)
  end.

%% @hidden
rollback(Repo, Value) ->
  case in_transaction(Repo) of
    true  ->
      error(Value);
    false ->
      xdb_exception:no_transaction_is_active()
  end.

%%%===================================================================
%%% Internal functions
%%%===================================================================

% @private
do_insert(Pid, #{schema := Schema, source := Source}, Fields0) ->
  maybe_transaction(Pid, fun() ->
    {Query, Params} = xdb_sql:i(Source, maps:to_list(Fields0)),
    case mysql:query(Pid, lists:flatten(Query), Params) of
      ok ->
        #{fields := SchemaSpec} = Schema:schema_spec(),
        PrimaryField = [Field || {Field, _, Options} <- SchemaSpec, [] == ?AUTO_PK -- Options],
        case PrimaryField of
          [] ->
            {ok, normalize(Schema, Fields0)};
          [Key] ->
            AutoId = mysql:insert_id(Pid),
            {ok, normalize(Schema, Fields0#{Key => AutoId})}
        end;
      {error, {1062, _, _}} ->
        {error, conflict};
      {error, {Code, _SqlState, Reason}} ->
        Description = <<"Error with Code:", (integer_to_binary(Code))/binary,
          " and Reason:", Reason/binary>>,
        error({db_error, Description})
    end
  end).

% @private
do_insert_all(Pid, #{schema := Schema} = Meta, List0) ->
  {Query, Params} = xdb_sql:i_all(Meta, List0),

  maybe_transaction(Pid, fun() ->
    case mysql:query(Pid, lists:flatten(Query), Params) of
      ok ->
        List = [normalize(Schema, Fields) || Fields <- List0],
        {length(List), List};
      {error, {1062, _, _}} ->
        {error, conflict};
      {error, {Code, _SqlState, Reason}} ->
        Description = <<"Error with Code:", (integer_to_binary(Code))/binary,
          " and Reason:", Reason/binary>>,
        error({db_error, Description})
    end
  end).

%% @private
do_execute(Pid, all, Schema, Source, Query) ->
  Conditions = normalize_query(maps:get(where, Query, [])),
  SelectFields = maps:get(select, Query, []),
  Limit = maps:get(limit, Query, 0),
  Offset = maps:get(offset, Query, 0),

  {Query0, Params} = xdb_sql:s(Source, SelectFields, Conditions, [], Offset, Limit, ""),

  maybe_transaction(Pid, fun() ->
    case mysql:query(Pid, lists:flatten(Query0), Params) of
      {ok, Key, Values} ->
        Result0 = [res_to_map(Key, Value, []) || Value <- Values],
        Result = [normalize(Schema, Field) || Field <- Result0],
        {length(Result), Result};
      {error, {Code, _SqlState, Reason}} ->
        Description = <<"Error with Code:", (integer_to_binary(Code))/binary,
          " and Reason:", Reason/binary>>,
        error({db_error, Description})
    end
  end);
do_execute(Pid, delete_all, _Schema, Source, Query) ->
  Conditions = normalize_query(maps:get(where, Query, [])),

  {CountQuery, CountParams}= get_count_query(Source, Conditions),
  {DQuery, DParams} = get_delete_query(Source, Conditions),

  maybe_transaction(Pid, fun() ->
    Count = do_count(Pid, CountQuery, CountParams),
    case mysql:query(Pid, lists:flatten(DQuery), DParams) of
      ok ->
        {Count, undefined};
      {error, {Code, _SqlState, Reason}} ->
        Description = <<"Error with Code:", (integer_to_binary(Code))/binary,
            " and Reason:", Reason/binary>>,
        error({db_error, Description})
    end
  end);
do_execute(Pid, update_all, _Schema, Source, Query) ->
  Conditions = normalize_query(maps:get(where, Query, [])),
  UpdateFields = normalize_query(maps:get(updates, Query, [])),

  {CountQuery, CountParams}= get_count_query(Source, Conditions),
  {UQuery, UParams, WParams} = xdb_sql:u(Source, UpdateFields, Conditions),

  maybe_transaction(Pid, fun() ->
    Count = do_count(Pid, CountQuery, CountParams),
    case mysql:query(Pid, lists:flatten(UQuery), UParams ++ WParams) of
      ok ->
        {Count, undefined};
      {error, {Code, _SqlState, Reason}} ->
        Description = <<"Error with Code:", (integer_to_binary(Code))/binary,
            " and Reason:", Reason/binary>>,
        error({db_error, Description})
      end
  end).

do_update(Pid, _Repo, Filters, Schema, Source, #{updates := []}) ->
  GetQuery = get_query(Filters),
  {_, [Result]} = do_execute(Pid, all, Schema, Source, GetQuery),
  {ok, Result};
do_update(Pid, _Repo, Filters, Schema, Source, Query) ->
  Conditions = normalize_query(maps:get(where, Query, [])),
  UpdateFields = normalize_query(maps:get(updates, Query, [])),
  {CountQuery, CountParams}= get_count_query(Source, Conditions),
  {UQuery, UParams, WParams} = xdb_sql:u(Source, UpdateFields, Conditions),

  maybe_transaction(Pid, fun() ->
    Count = do_count(Pid, CountQuery, CountParams),
    case Count of
      0 ->
        {error, stale};
      _ ->
        case mysql:query(Pid, lists:flatten(UQuery), UParams ++ WParams) of
          ok ->
            GetQuery = get_query(Filters),
            {_, [Result]} = do_execute(Pid, all, Schema, Source, GetQuery),
            {ok, Result};
          {error, {Code, _SqlState, Reason}} ->
            Description = <<"Error with Code:", (integer_to_binary(Code))/binary,
                " and Reason:", Reason/binary>>,
            error({db_error, Description})
        end
    end
  end).

do_delete(Pid, _Repo, Filters, Schema, Source, Query) ->
  Conditions = normalize_query(maps:get(where, Query, [])),

  {CountQuery, CountParams}= get_count_query(Source, Conditions),
  {DQuery, DParams} = get_delete_query(Source, Conditions),
  maybe_transaction(Pid, fun() ->
    Count = do_count(Pid, CountQuery, CountParams),
    case Count of
      0 ->
        {error, stale};
      _ ->
        GetQuery = get_query(Filters),
        {_, [Fields]} = do_execute(Pid, all, Schema, Source, GetQuery),
        case mysql:query(Pid, lists:flatten(DQuery), DParams) of
          ok ->
            {ok, Fields};
          {error, {Code, _SqlState, Reason}} ->
            Description = <<"Error with Code:", (integer_to_binary(Code))/binary,
                " and Reason:", Reason/binary>>,
            error({db_error, Description})
        end
    end
  end).

%% @private
do_count(Pid, CountQuery, CountParams) ->
  case mysql:query(Pid, lists:flatten(CountQuery), CountParams) of
    {ok, _Key, [[Count0]]} ->
      Count0;
    {error, {Code0, _SqlState0, Reason0}} ->
      Description0 = <<"Error with Code:", (integer_to_binary(Code0))/binary,
        " and Reason:", Reason0/binary>>,
      error({db_error, Description0})
  end.

%% @private
get_query(Conditions) ->
  #{
    select  => [],
    where   => Conditions,
    limit   => 0,
    offset  => 0
  }.

%% @private
get_count_query(Source, []) ->
  xdb_sql:s_count(Source, [], []);
get_count_query(Source, Conditions) ->
  xdb_sql:s_count(Source, [], Conditions, []).

%% @private
get_delete_query(Source, []) ->
  xdb_sql:d(Source);
get_delete_query(Source, Conditions) ->
  xdb_sql:d(Source, Conditions).

%% @private
pool_name(Repo) ->
  list_to_atom(atom_to_list(Repo) ++ "_pool").

%% @private
pool_args(Name, Opts) ->
  PoolSize = xdb_lib:keyfind(pool_size, Opts, ?DEFAULT_POOL_SIZE),
  MaxOverflow = xdb_lib:keyfind(pool_max_overflow, Opts, PoolSize),

  [
    {name, {local, Name}},
    {worker_module, mysql},
    {size, PoolSize},
    {max_overflow, MaxOverflow}
  ].

%% @private
parse_opts(Opts) ->
  _ = xdb_lib:keyfind(database, Opts),
  parse_opts(Opts, []) .

%% @private
parse_opts([], Acc) ->
  Acc;
parse_opts([{hostname, Value} | Opts], Acc) ->
  parse_opts(Opts, [{host, Value} | Acc]);
parse_opts([{username, Value} | Opts], Acc) ->
  parse_opts(Opts, [{user, Value} | Acc]);
parse_opts([{ssl_opts, Value} | Opts], Acc) ->
  parse_opts(Opts, [{ssl, Value} | Acc]);
parse_opts([Opt | Opts], Acc) ->
  parse_opts(Opts, [Opt | Acc]).

%% add more for data types conversion
normalize(Schema, Fields) ->
  #{fields := SchemaSpec} = Schema:schema_spec(),
  BooleanFields = [Field || {Field, boolean, _} <- SchemaSpec],

  NormalizedBooleanField = normalize_boolean(Fields, BooleanFields),
  Pred0 = fun(_K, V) -> V =/= undefined end,
  maps:filter(Pred0, NormalizedBooleanField).

normalize_boolean(NormalizedField, []) ->
  NormalizedField;
normalize_boolean(NormalizedField, [BooleanField | Remaining]) ->
  Value = maps:get(BooleanField, NormalizedField, undefined),
  normalize_boolean(convert(NormalizedField, BooleanField, Value), Remaining).

convert(NormalizedField, BooleanField, true) ->
  NormalizedField#{BooleanField => 1};
convert(NormalizedField, BooleanField, false) ->
  NormalizedField#{BooleanField => 0};
convert(NormalizedField, BooleanField, 1) ->
  NormalizedField#{BooleanField => true};
convert(NormalizedField, BooleanField, 0) ->
  NormalizedField#{BooleanField => false};
convert(NormalizedField, _BooleanField, _) ->
  NormalizedField.

%% @private
res_to_map([], [], Acc) ->
  maps:from_list(Acc);
res_to_map([K| Key], [V| Value], Acc) ->
  res_to_map(Key, Value, [{binary_to_atom(K, utf8), get_value(V)}] ++ Acc).

get_value(null) ->
  undefined;
get_value(Value) ->
  Value.

normalize_query([{Key, Values}]) when is_list(Values) ->
  [{Key, [normalize_query(Value) || Value <- Values]}];
normalize_query(Params) when is_list(Params) ->
  [normalize_query(Param) || Param <- Params];
normalize_query({ConditionalOperator, Params}) when is_list(Params) ->
  {ConditionalOperator, normalize_query(Params)};
normalize_query([{Key, undefined}]) ->
  [{Key, null}];
normalize_query([{Key, Op, undefined}]) ->
  [{Key, Op, null}];
normalize_query([{Key, Value}]) ->
  [{Key, Value}];
normalize_query([{Key, Op, Value}]) ->
  [{Key, Op, Value}];
normalize_query({Key, undefined}) ->
  {Key, null};
normalize_query({Key, Op, undefined}) ->
  {Key, Op, null};
normalize_query({Key, Value}) ->
  {Key, Value};
normalize_query({Key, Op, Value}) ->
  {Key, Op, Value};
normalize_query([]) ->
  [].

%% based on data types...
transform(Filters) ->
  [{K, '==', V} || {K, V} <- Filters, V =/= undefined].

exec_transaction(Pid, Fun) ->
  exec_transaction(Pid, Fun, fun xdb_lib:raise/1).

%% @private
exec_transaction(Pid, Fun, ErrorFun) ->
  case mysql:transaction(Pid, Fun) of
    {atomic, Result} ->
      Result;
    {aborted, Reason} ->
      ErrorFun(Reason)
  end.

%% @private
maybe_transaction(Pid, Fun) ->
  maybe_transaction(Pid, Fun, mysql:in_transaction(Pid)).

%% @private
maybe_transaction(_Pid, Fun, true) ->
  Fun();
maybe_transaction(Pid, Fun, false) ->
  exec_transaction(Pid, Fun).
