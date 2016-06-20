module std.database.postgres.bindings;
import core.stdc.config;

extern(System) {

    // from server/catalog/pg_type.h
    enum int BOOLOID = 16;
    enum int BYTEAOI = 17;
    enum int CHAROID = 18;
    enum int NAMEOID = 19;
    enum int INT8OID = 20;
    enum int INT2OID = 21;
    enum int INT2VECTOROID = 22;
    enum int INT4OID = 23;
    enum int REGPROCOID = 24;
    enum int TEXTOID = 25;
    enum int OIDOID = 26;
    enum int TIDOID = 27;
    enum int XIDOID = 28;
    enum int CIDOID = 29;
    enum int OIDVECTOROID = 30;
    enum int VARCHAROID = 1043;
    enum int DATEOID = 1082;


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

    PGresult *PQexecParams(
            PGconn *conn,
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
    char *PQfname(const PGresult *res, int field_num);

    void PQclear(PGresult *res);

    char *PQresultErrorMessage(const PGresult *res);

    // date

    /* see pgtypes_date.h */

    alias long date; // long?
    void PGTYPESdate_julmdy(date, int *);
    void PGTYPESdate_mdyjul(int *mdy, date *jdate);

    // numeric

    enum int DECSIZE = 30;

    alias ubyte NumericDigit;

    struct numeric {
        int			ndigits;		/* number of digits in digits[] - can be 0! */
        int			weight;			/* weight of first digit */
        int			rscale;			/* result scale */
        int			dscale;			/* display scale */
        int			sign;			/* NUMERIC_POS, NUMERIC_NEG, or NUMERIC_NAN */
        NumericDigit *buf;			/* start of alloc'd space for digits[] */
        NumericDigit *digits;		/* decimal digits */
    };

    struct decimal {
        int			ndigits;		/* number of digits in digits[] - can be 0! */
        int			weight;			/* weight of first digit */
        int			rscale;			/* result scale */
        int			dscale;			/* display scale */
        int			sign;			/* NUMERIC_POS, NUMERIC_NEG, or NUMERIC_NAN */
        NumericDigit[DECSIZE] digits;		/* decimal digits */
    }

    int PGTYPESnumeric_to_int(numeric *nv, int *ip);

    // non blocking calls

    alias PostgresPollingStatusType = int;
    enum {
        PGRES_POLLING_FAILED = 0,
        PGRES_POLLING_READING,		/* These two indicate that one may	  */
        PGRES_POLLING_WRITING,		/* use select before polling again.   */
        PGRES_POLLING_OK,
        PGRES_POLLING_ACTIVE		/* unused; keep for awhile for backwards
                                     * compatibility */
    } 

    PostgresPollingStatusType PQconnectPoll(PGconn *conn);

    int	PQsocket(const PGconn *conn);

    int PQsendQuery(PGconn *conn, const char *command);

    int PQsendQueryParams(
            PGconn *conn,
            const char *command,
            int nParams,
            const Oid *paramTypes,
            const char ** paramValues,
            const int *paramLengths,
            const int *paramFormats,
            int resultFormat);

    int PQsendQueryPrepared(
            PGconn *conn,
            const char *stmtName,
            int nParams,
            const char **paramValues,
            const int *paramLengths,
            const int *paramFormats,
            int resultFormat);

    int PQsendDescribePrepared(PGconn *conn, const char *stmtName);
    int	PQsendDescribePrepared(PGconn *conn, const char *stmt);
    int PQconsumeInput(PGconn *conn);
    int PQisBusy(PGconn *conn);
    int PQsetnonblocking(PGconn *conn, int arg);
    int PQisnonblocking(const PGconn *conn);

    int	PQflush(PGconn *conn);

    struct PGnotify {
        char* relname;
        int be_pid;
        char* extra;
        private PGnotify* next;
    }

    PGnotify *PQnotifies(PGconn *conn);
    void PQfreemem(void *ptr);

}

