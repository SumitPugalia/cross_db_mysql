%%%-------------------------------------------------------------------
%%% @doc
%%% Main Application.
%%% @end
%%%-------------------------------------------------------------------
-module(xdb_mysql).

-behaviour(application).
-behaviour(supervisor).

%% Application callbacks
-export([
  start/2,
  stop/1
]).

%% Supervisor callbacks
-export([init/1]).

%%%===================================================================
%%% Application callbacks
%%%===================================================================

%% @hidden
start(_StartType, _StartArgs) ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% @hidden
stop(_State) ->
  ok.

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%% @hidden
init([]) ->
  {ok, {{one_for_one, 10, 10}, []}}.
