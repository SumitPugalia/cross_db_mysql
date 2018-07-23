-module(xdb_mysql_query_conditions_SUITE).

%% Common Test
-export([
  all/0,
  init_per_suite/1,
  end_per_suite/1
]).

%% Test Cases
-export([
  t_order_by/1
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

%%%===================================================================
%%% Test Cases
%%%===================================================================

-spec t_order_by(xdb_ct:config()) -> ok.
t_order_by(Config) ->
  Repo = xdb_lib:keyfetch(repo, Config),

  #{
    1 := #{'__meta__' := _, first_name := <<"Alan">>, last_name := <<"Turing">>, age := 41},
    2 := #{'__meta__' := _, first_name := <<"Charles">>, last_name := <<"Darwin">>, age := 73},
    3 := #{'__meta__' := _, first_name := <<"Alan">>, last_name := <<"Poe">>, age := 40},
    4 := #{'__meta__' := _, first_name := <<"John">>, last_name := <<"Lennon">>, age:= 40}
  } = All = person:list_to_map(Repo:all(person)),
  4 = maps:size(All),

  DescQuery = xdb_query:from(person, [{order_by, [{age, desc}]}]),
  #{
    2 := #{'__meta__' := _, first_name := <<"Charles">>, last_name := <<"Darwin">>, age := 73},
    1 := #{'__meta__' := _, first_name := <<"Alan">>, last_name := <<"Turing">>, age := 41},
    3 := #{'__meta__' := _, first_name := <<"Alan">>, last_name := <<"Poe">>, age := 40},
    4 := #{'__meta__' := _, first_name := <<"John">>, last_name := <<"Lennon">>, age:= 40}
  } = All2 = person:list_to_map(Repo:all(DescQuery)),
  4 = maps:size(All2),

  AscQuery = xdb_query:from(person, [{order_by, [{age, asc}]}]),
  #{
    3 := #{'__meta__' := _, first_name := <<"Alan">>, last_name := <<"Poe">>, age := 40},
    4 := #{'__meta__' := _, first_name := <<"John">>, last_name := <<"Lennon">>, age:= 40},
    1 := #{'__meta__' := _, first_name := <<"Alan">>, last_name := <<"Turing">>, age := 41},
    2 := #{'__meta__' := _, first_name := <<"Charles">>, last_name := <<"Darwin">>, age := 73}
  } = All3 = person:list_to_map(Repo:all(AscQuery)),
 4 = maps:size(All3),
 ok.