# dstddb
## A proposed standard database client interface and implementation for the [D](http://dlang.org) Language

Status: early stage project - unstable and minimally tested

Available in [DUB](https://code.dlang.org/packages/dstddb), the D package registry

### Roadmap Highlights
- A database and driver neutral interface specification
- Reference counted value objects provide ease of use
- Templated implementations for Phobos compatibility 
- Support for direct and polymorphic interfaces
- A range interface for query result sets
- Support a for [fluent](http://en.wikipedia.org/wiki/Fluent_interface) style interface
- URL style connection strings
- Reference implementations so far: mysql, sqlite, oracle, and ODBC
- Support for allocators
- Support for runtime driver registration
- Input variable binding support
- Array input/output binding support
- Connection pooling

## Examples

#### simple execute
```D
import std.database.mysql;
auto db = createDatabase("mysql://database");
db.execute("insert into table('name',123)");
```

#### expanded classic style select
```D
import std.database.mysql;
auto db = createDatabase("mysql://127.0.0.1/test");
auto con = db.connection();
auto stmt = con.statement("select * from table");
auto rowSet = stmt.execute();
auto range = stmt[];
foreach (row; range) {
    for(size_t col = 0; col != row.columns; ++col) write(rowr[col]), " ");
    writeln();
}

```
#### [fluent](http://en.wikipedia.org/wiki/Fluent_interface) style select
```D
import std.database.sqlite;
createDatabase("file:///demo.sqlite")
    .connection()
    .execute("select * from t1")
    .writeResult();
    ```

#### field access
    ```D
import std.database.sqlite;
auto db = createDatabase("file:///testdb");
auto rowSet = db.connection().execute("select name,score from score");
foreach (r; rowSet) {
    writeln(r[0].as!string,",",r[1].as!int);
}

```

#### select with input binding
```D
import std.database.sqlite;
int minScore = 50;
createDatabase("file:///demo.sqlite")
    .connection()
    .execute("select * from t1 where score >= ?", minScore)
    .writeResult();
    ```

#### insert with input binding
    ```D
    import std.database;
    auto db = createDatabase("mydb");
    auto con = db.connection();
    auto stmt = con.statement("insert into table values(?,?)");
    stmt.execute("a",1);
    stmt.execute("b",2);
    stmt.execute("c",3);
    ```

#### poly database setup (driver registration)
    ```D
    import std.database.poly;
    Database.register!(std.database.sqlite.Database)();
    Database.register!(std.database.mysql.Database)();
    Database.register!(std.database.oracle.Database)();
    auto db = createDatabase("mydb");
    ```

## Status

    WIP

    | Feature                      | sqlite | mysql  | oracle | postgres | odbc  | poly  |
    | :--------------------------- | :----- | :----- | :----- | :------  | :---- | :---- |
    | command only execution       | y      | y      | y      | y        | y     |       |
    | select no-bind with results  | y      | y      | y      | y        | y     |       |
    | input binding (string only)  | y      | y      | y      | y        |       |       |
    | native column type buffers   |        | y      |        |          |       |       |

