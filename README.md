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
- Reference implementations so far: ODBC, sqlite, mysql, oracle, postgres, freetds (MS SQL)
- Support for allocators
- Support for runtime driver registration
- Input variable binding support
- Array input/output binding support
- Connection pooling

### Related Work
[CPPSTDDB](https://github.com/cruisercoder/cppstddb) is a related project with
similar objectives tailored to the constraints of the C++ language.  The aim is
for both projects to complement each other by proving the validity of specific
design choices that apply to both and to draw on implementation correctness 
re-enforced from dual language development.

## Examples

#### simple query
```D
import std.database.mysql;
auto db = createDatabase("mysql://database");
db.query("insert into table('name',123)");
```

#### expanded classic style select
```D
import std.database.mysql;
auto db = createDatabase("mysql://127.0.0.1/test");
auto con = db.connection();
auto stmt = con.statement("select * from table");
auto rows = stmt.query.rows;
foreach (row; rows) {
    for(size_t col = 0; col != row.width; ++col) write(row[col], " ");
    writeln();
}

```
#### [fluent](http://en.wikipedia.org/wiki/Fluent_interface) style select
```D
import std.database.sqlite;
createDatabase("file:///demo.sqlite")
    .connection
    .query("select * from t1")
    .writeRows;
```

#### field access
```D
import std.database.sqlite;
auto db = createDatabase("file:///testdb");
auto rows = db.connection.query("select name,score from score").rows;
foreach (r; rows) {
    writeln(r[0].as!string,",",r[1].as!int);
}
```

#### select with input binding
```D
import std.database.sqlite;
int minScore = 50;
createDatabase("file:///demo.sqlite")
    .connection
    .query("select * from t1 where score >= ?", minScore)
    .writeRows;
```

#### insert with input binding
```D
import std.database;
auto db = createDatabase("mydb");
auto con = db.connection();
auto stmt = con.statement("insert into table values(?,?)");
stmt.query("a",1);
stmt.query("b",2);
stmt.query("c",3);
```

#### poly database setup (driver registration)
```D
import std.database.poly;
Database.register!(std.database.sqlite.Database)();
Database.register!(std.database.mysql.Database)();
Database.register!(std.database.oracle.Database)();
auto db = createDatabase("mydb");
```

### Notes

- The reference implementations use logging (std.experimental.logger). To hide the info logging, add this line to your package.json file: "versions": ["StdLoggerDisableInfo"].

