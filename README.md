# cross_db_mysql
> ## MySQL adapter for CrossDB
> **Still in development stage!**

**cross_db_mysql** is used alongwith [CrossDB](https://github.com/cabol/cross_db).

## Testing

Before to run the tests you have run dialyzer first:

```
$ rebar3 dialyzer
```

Then run the tests like so:

```
$ rebar3 ct
```

And if you want to check the coverage:

```
$ rebar3 do ct, cover
```

## Copyright and License

Copyright (c) 2018 Sumit Pugalia

CrossDB source code is licensed under the [MIT License](LICENSE).
