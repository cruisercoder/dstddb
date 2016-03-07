module std.database.postgres.bindings;
import core.stdc.config;


extern(System) {

    enum PGRES_EMPTY_QUERY = 0;

    enum int CONNECTION_OK = 0;
    enum int PGRES_COMMAND_OK = 1;
    enum int PGRES_TUPLES_OK = 2;
    enum int PGRES_COPY_OUT = 3;
    enum int PGRES_COPY_IN = 4;
    enum int PGRES_BAD_RESPONSE = 5;
    enum int PGRES_NONFATAL_ERROR = 6;
    enum int PGRES_FATAL_ERROR = 7;
    enum int PGRES_COPY_BOTH = 8;
    enum int PGRES_SINGLE_TUPLE = 9;

    alias ExecStatusType=int;
    alias Oid=uint;

    struct PGconn {};

    PGconn* PQconnectdb(const char*);
    PGconn *PQconnectdbParams(const char **keywords, const char **values, int expand_dbname);
    void PQfinish(PGconn*);

    int PQstatus(PGconn*);
    const (char*) PQerrorMessage(PGconn*);

    struct PGresult {};

    int PQsendQuery(PGconn *conn, const char *command);
    PGresult *PQgetResult(PGconn *conn);

    int	PQsetSingleRowMode(PGconn *conn);

    ExecStatusType PQresultStatus(const PGresult *res);
    char *PQresStatus(ExecStatusType status);

    PGresult *PQexecParams(PGconn *conn,
            const char *command,
            int nParams,
            const Oid *paramTypes,
            const char ** paramValues,
            const int *paramLengths,
            const int *paramFormats,
            int resultFormat);

    PGresult *PQprepare(
            PGconn *conn,
            const char *stmtName,
            const char *query,
            int nParams,
            const Oid *paramTypes);

    /*
       PGresult *PQexecPrepared(
       PGconn *conn,
       const char *stmtName,
       int nParams,
       const char *const *paramValues,
       const int *paramLengths,
       const int *paramFormats,
       int resultFormat);
     */

    PGresult* PQexecPrepared(
            PGconn*,
            const char* stmtName,
            int nParams,
            const char** paramValues,
            const int* paramLengths,
            const int* paramFormats,
            int resultFormat);

    int	PQntuples(const PGresult *res);
    int PQnfields(PGresult*);

    char *PQgetvalue(const PGresult *res, int row_number, int column_number);
    int	PQgetlength(const PGresult *res, int tup_num, int field_num);
    int	PQgetisnull(const PGresult *res, int tup_num, int field_num);

    Oid PQftype(const PGresult *res, int column_number);
    int PQfformat(const PGresult *res, int field_num);

    void PQclear(PGresult *res);

}


