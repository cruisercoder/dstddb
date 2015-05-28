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

#### classic example
```D
import std.database;
auto db = Database();
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

#### [fluent](http://en.wikipedia.org/wiki/Fluent_interface) style example
```D
import std.database.sqlite;
Database()
    .connection("file://demo.sqlite");
    .statement("select * from t1")
    .range()
    .write_result();
```

#### input binding example
```D
import std.database.sqlite;
int minScore = 50;
Database()
    .connection("file://demo.sqlite");
    .statement("select * from t1 where score >= ?", minScore)
    .range()
    .write_result();
```

#### poly database setup (driver registration) example
```D
import std.database;
Database.register!(std.database.sqlite.Database)();
Database.register!(std.database.mysql.Database)();
Database db;
```

## Quickstart (OSX, homebrew)
```bash
brew install dmd,dub,sqlite,mysql
https://github.com/cruisercoder/ddb
cd ddb
dub
```

## Implementation Notes

- Support for native drivers provides first class parity with interfaces in other languages.  It also simplifies dependencies. Native drivers will also perform better for certain use cases.
- The major interface objects (Database, Statement, ResultRange) are reference counted structs (no GC) to support deterministic cleanup of resources. Row and Value are proxy structs.
- The poly driver uses type erasure to front other drivers and allows both runtime registration and target driver selection


## TODO

A very incomplete list

- Add optional config parameter to Database for a variety of preferences. This can also include a default database source for connections.
- Add a resolver hook to the Database object to resolve named sources
- separate out dub build targets for each reference native driver
- factor out native layer stubs (oracle) but retain for testing
- variadic input variable binder
- logging support
