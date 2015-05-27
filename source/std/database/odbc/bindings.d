module std.database.odbc.bindings;

// nothing right here yet, just a test

enum
SQL_HANDLE_ENV = 0x00000001,
SQL_NULL_HANDLE = 0x00000002;

alias int SQLRETURN;

extern(System) {

    int SQLAllocHandle(
            int,
            int,
            void**) {return 0;}

    int SQLFreeHandle(
            int,
            void*) {return 0;}
}

