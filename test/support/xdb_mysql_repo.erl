-module(xdb_mysql_repo).

-include_lib("cross_db/include/xdb.hrl").
-repo([{otp_app, cross_db_mysql}, {adapter, xdb_mysql_adapter}]).
