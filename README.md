# ddb
## A proposed standard database client interface for the [D Language](http://dlang.org)

Status: early stage project (only a few things are working)

### Highlights
- A database and driver neutral interface specification
- Support for native (direct) drivers on the C interface or wire protocol
- A polymorphic driver with runtime target registration and target driver selection
- A range interface to query result sets (single pass range)
- Support for [fluent](http://en.wikipedia.org/wiki/Fluent_interface) style interface
- Included reference implementations: mysql, sqlite, oracle, and ODBC
- Support for multiple implementations of same db type
- Input variable binding support
- Array input/output binding support
- Automatic connection pooling
- URL style connection string

## Examples

#### classic example
```D
auto db = Database();
auto con = db.connection("file://test.sqlite");
auto stmt = con.statement("select * from table");
auto range = stmt.range();
foreach (Row r; range) {
    for(size_t c = 0; c != r.columns; ++c) {
        write(r[c].toString(), " ");
    }
    writeln();
}
```

#### [fluent](http://en.wikipedia.org/wiki/Fluent_interface) style example
```D
Database()
    .connection("file://demo.sqlite");
    .statement("select * from t1")
    .range()
    .write_result();
```

#### poly database setup (driver registration) example
```D
import std.database.poly.database;
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

- simplify package hierarchy for user code import (std.database.mysql vs std.database.mysql.Database)
- Add optional config parameter to Database for a variety of preferences. This can also include a default database source for connections.
- Add a resolver hook to the Database object to resolve named sources
- separate out dub build targets for each reference native driver 
- factor out native layer stubs (oracle) but retain for testing
- variadic input variable binder
- logging support


