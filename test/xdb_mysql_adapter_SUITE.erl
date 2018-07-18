-module(xdb_mysql_adapter_SUITE).

%% Common Test
-export([
  all/0,
  init_per_suite/1,
  end_per_suite/1
]).

%% Test Cases
-export([
  t_pool/1,
  t_insert_all/1,
  t_insert_errors/1,
  t_insert_autoincrement/1,
  t_update_empty/1
]).

%% Test Cases
-include_lib("mixer/include/mixer.hrl").
-mixin([
  {xdb_repo_basic_test, [
    % CT
    init_per_testcase/2,
    end_per_testcase/2,

    % Test Cases
      t_insert/1,
      t_update/1,
      t_delete/1,
      t_get/1,
      t_get_by/1,
      t_all/1,
      t_all_with_pagination/1,
      t_delete_all/1,
      t_delete_all_with_conditions/1,
      t_update_all/1,
      t_update_all_with_conditions/1
  ]}
]).

-import(xdb_ct, [assert_error/2]).

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

-spec t_pool(xdb_ct:config()) -> ok.
t_pool(Config) ->
  Repo = xdb_lib:keyfetch(repo, Config),
  Pool = list_to_atom(atom_to_list(Repo) ++ "_pool"),
  {ready, 5, 0, 0} = poolboy:status(Pool),
  ok.

-spec t_insert_all(xdb_ct:config()) -> ok.
t_insert_all(Config) ->
  Repo = xdb_lib:keyfetch(repo, Config),
  [] = Repo:all(person),

  People = [
    #{id => 1, first_name => "Alan", last_name => "Turing", age => 41, is_blocked => true},
    #{id => 2, first_name => "Charles", last_name => "Darwin", age => 73},
    #{id => 3, first_name => "Alan", last_name => "Poe", age => 40}
  ],

  {3, _} = Repo:insert_all(person, People),

  #{
    1 := #{'__meta__' := _, first_name := <<"Alan">>, last_name := <<"Turing">>},
    2 := #{'__meta__' := _, first_name := <<"Charles">>, last_name := <<"Darwin">>},
    3 := #{'__meta__' := _, first_name := <<"Alan">>, last_name := <<"Poe">>}
  } = All1 = person:list_to_map(Repo:all(person)),
  3 = maps:size(All1),
  ok.

-spec t_insert_errors(xdb_ct:config()) -> ok.
t_insert_errors(Config) ->
  Repo = xdb_lib:keyfetch(repo, Config),

  {error, CS} =
    xdb_ct:pipe(#{id => 1}, [
      {fun person:schema/1, []},
      {fun xdb_changeset:change/2, [#{first_name => <<"Joe">>}]},
      {fun xdb_changeset:add_error/3, [first_name, <<"Invalid">>]},
      {fun Repo:insert/1, []}
    ]),

  ok = assert_error(fun() -> Repo:update(CS) end, badarg).

-spec t_insert_autoincrement(xdb_ct:config()) -> ok.
t_insert_autoincrement(Config) ->
  Repo = xdb_lib:keyfetch(repo, Config),
  {ok, #{id := Id}} = Repo:insert(autoincrement:schema()),
  true = (Id =/= undefined).

-spec t_update_empty(xdb_ct:config()) -> ok.
t_update_empty(Config) ->
  Repo = xdb_lib:keyfetch(repo, Config),
  ok = seed(Config),
  Person = Repo:get(person, 1),

  {ok, _CS} =
    xdb_ct:pipe(Person, [
      {fun person:changeset/2, [#{}]},
      {fun Repo:update/1, []}
    ]),

  Person = Repo:get(person, 1),
  ok.

%%%===================================================================
%%% Helpers
%%%===================================================================

-spec seed(xdb_ct:config()) -> ok.
seed(Config) ->
  Repo = xdb_lib:keyfetch(repo, Config),

  People = [
    person:schema(#{id => 1, first_name => "Alan", last_name => "Turing", age => 41}),
    person:schema(#{id => 2, first_name => "Charles", last_name => "Darwin", age => 73}),
    person:schema(#{id => 3, first_name => "Alan", last_name => "Poe", age => 40})
  ],

  _ = [_ = Repo:insert_or_raise(P) || P <- People],
  ok.