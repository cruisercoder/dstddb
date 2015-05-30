# ddb
## A proposed standard database client interface for the [D](http://dlang.org) Language

Status: early stage project (only a few things are working)

### Highlights
- A database and driver neutral interface specification
- Support for native and polymorphic drivers
- A range interface for query result sets (single pass range)
- Support a for [fluent](http://en.wikipedia.org/wiki/Fluent_interface) style interface
- Included reference implementations: mysql, sqlite, oracle, and ODBC
- Support for runtime driver registration
- Input variable binding support
- Array input/output binding support
- Connection pooling
- URL style connection strings

## Examples

#### simple execute
```D
import std.database;
auto db = Database.create("mydb");
db.execute("insert into table('name',123)");
```

#### [fluent](http://en.wikipedia.org/wiki/Fluent_interface) style
```D
import std.database.sqlite;
Database.create("file://demo.sqlite");
    .connection()
    .statement("select * from t1")
    .range()
    .write_result();
```

#### classic select
```D
import std.database;
auto db = Database.create("defaultdb");
auto con = db.connection("mydb");
auto stmt = con.statement("select * from table");
auto range = stmt.range();
foreach (Row row; range) {
    for(size_t col = 0; col != row.columns; ++row) {
        write(rowr[col]), " ");
    }
    writeln();
}
```

#### select with input binding
```D
import std.database.sqlite;
int minScore = 50;
Database.create("file://demo.sqlite")
    .connetion()
    .statement("select * from t1 where score >= ?", minScore)
    .range()
    .write_result();
```

#### insert with input binding
```D
import std.database;
auto db = Database.create("mydb");
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
auto db = Database.create("mydb");
```

## Quickstart (OSX, homebrew)
```bash
brew install dmd,dub,sqlite,mysql
https://github.com/cruisercoder/ddb
cd ddb
dub
```

## Status

| Feature                 | sqlite | mysql  | oracle | odbc  |
| :---------------------- | :----- | :----- | :----- | :---- |
| simple sql select       | y      |        |        |       |


## Implementation Notes

- Support for native drivers provides first class parity with interfaces in other languages.  It also simplifies dependencies. Native drivers will also perform better for certain use cases.
- The major interface objects (Database, Statement, ResultRange) are reference counted structs (no GC) to support deterministic cleanup of resources. Row and Value are proxy structs.
- The poly driver uses type erasure to front other drivers and allows both runtime registration and target driver selection


## TODO

A very incomplete list

- Add optional config parameter to Database for a variety of preferences. 
- Add a resolver hook to the Database object to resolve named sources
- separate out dub build targets for each reference native driver
- factor out native layer stubs (oracle) but retain for testing
- variadic input variable binder
- logging support
