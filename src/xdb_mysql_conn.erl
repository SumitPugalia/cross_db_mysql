%%%-------------------------------------------------------------------
%%% @doc
%%% Pool worker.
%%% @end
%%%-------------------------------------------------------------------
-module(xdb_mysql_conn).

-behaviour(gen_server).
-behaviour(poolboy_worker).

%% API
-export([
  start_link/1
]).

%% gen_server callbacks
-export([
  init/1,
  handle_call/3,
  handle_cast/2
]).

%%%===================================================================
%%% API
%%%===================================================================

-spec start_link(Opts) -> Res when
  Opts :: xdb_lib:keyword(),
  Res  :: {ok, pid()} | {error, any()}.
start_link(Opts) when is_list(Opts) ->
  gen_server:start_link(?MODULE, Opts, []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @hidden
init(Opts) ->
  _ = process_flag(trap_exit, true),
  {ok, Conn} = mysql:start_link(Opts),
  {ok, #{conn => Conn}}.

%% @hidden
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

%% @hidden
handle_cast(_Request, State) ->
  {noreply, State}.
