-module(autoincrement).

-include_lib("cross_db/include/xdb.hrl").
-schema({autoincrement, [
  {id, integer, [primary_key, autogenerate_id]}
]}).