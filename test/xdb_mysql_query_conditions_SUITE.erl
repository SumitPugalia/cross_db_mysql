-module(xdb_mysql_query_conditions_SUITE).


%% Common Test
-export([
  all/0,
  init_per_suite/1,
  end_per_suite/1
]).

-include_lib("mixer/include/mixer.hrl").
-mixin([
  {xdb_query_conditions_test, [
    % CT
    init_per_testcase/2,
    end_per_testcase/2,

    % Test Cases
    t_all/1,
    t_or_conditional/1,
    t_and_conditional/1,
    t_not_conditional/1,
    t_not_null_conditional/1,
    t_null_conditional/1,
    t_operators/1,
    t_like_operator/1,
    t_deeply_nested/1
  ]}
]).

-define(EXCLUDED_FUNS, [
  module_info,
  all,
  init_per_suite,
  end_per_suite,
  init_per_testcase,
  end_per_testcase
]).

-include_lib("stdlib/include/ms_transform.hrl").

%%%===================================================================
%%% CT
%%%===================================================================

-spec all() -> [atom()].
all() ->
  Exports = ?MODULE:module_info(exports),
  [F || {F, _} <- Exports, not lists:member(F, ?EXCLUDED_FUNS)].

-spec init_per_suite(xdb_ct:config()) -> xdb_ct:config().
init_per_suite(Config) ->
  {ok, _} = application:ensure_all_started(cross_db_mysql),
  [{repo, xdb_mysql_repo} | Config].

-spec end_per_suite(xdb_ct:config()) -> ok.
end_per_suite(_) ->
  ok = application:stop(cross_db_mysql).
