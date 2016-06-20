module std.database.freetds.bindings;
import core.stdc.config;

extern(System) {
    alias RETCODE = int;

    alias int DBINT;
    alias ubyte BYTE;
    alias int STATUS;

    enum {
        REG_ROW = -1,
        MORE_ROWS = -1,
        NO_MORE_ROWS = -2,
        BUF_FULL = -3,
        NO_MORE_RESULTS = 2,
        SUCCEED = 1,
        FAIL = 0
    }

    enum {
        INT_EXIT = 0,
        INT_CONTINUE = 1,
        INT_CANCEL = 2,
        INT_TIMEOUT = 3
    }

    enum {
        DBSETHOST = 1, /* this sets client host name */
        DBSETUSER = 2,
        DBSETPWD = 3,
        DBSETHID = 4,       /* not implemented */
        DBSETAPP = 5,
        DBSETBCP = 6,
        DBSETNATLANG = 7,
        DBSETNOSHORT = 8,	/* not implemented */
        DBSETHIER = 9,      /* not implemented */
        DBSETCHARSET = 10,
        DBSETPACKET = 11,
        DBSETENCRYPT = 12,
        DBSETLABELED = 13,
        DBSETDBNAME = 14
    }

    enum {
        SYBCHAR = 47,
        SYBVARCHAR = 39,
        SYBINTN = 38,
        SYBINT1 = 48,
        SYBINT2 = 52,
        SYBINT4 = 56,
        SYBINT8 = 127,
        SYBFLT8 = 62,
        SYBDATETIME = 61,
        SYBBIT = 50,
        SYBBITN = 104,
        SYBTEXT = 35,
        SYBNTEXT = 99,
        SYBIMAGE = 34,
        SYBMONEY4 = 122,
        SYBMONEY = 60,
        SYBDATETIME4 = 58,
        SYBREAL = 59,
        SYBBINARY = 45,
        SYBVOID = 31,
        SYBVARBINARY = 37,
        SYBNUMERIC = 108,
        SYBDECIMAL = 106,
        SYBFLTN = 109,
        SYBMONEYN = 110,
        SYBDATETIMN = 111,
        SYBNVARCHAR = 103,

        SYBMSDATE = 40
    };

    enum {
        NTBSTRINGBIND = 2,
        DATETIMEBIND = 11
    }

    struct DBDATETIME {
        DBINT dtdays;
        DBINT dttime;
    }

    struct tds_microsoft_dbdaterec {
        DBINT year;     /* 1753 - 9999         */
        DBINT quarter;      /* 1 - 4           */
        DBINT month;        /* 1 - 12          */
        DBINT day;      /* 1 - 31          */
        DBINT dayofyear;    /* 1 - 366         */
        DBINT week;             /* 1 - 54 (for leap years) */
        DBINT weekday;      /* 1 - 7 (Mon. - Sun.)     */
        DBINT hour;     /* 0 - 23          */
        DBINT minute;       /* 0 - 59          */
        DBINT second;       /* 0 - 59          */
        DBINT millisecond;  /* 0 - 999         */
        DBINT tzone;        /* -840 - 840          */
    };

    struct tds_microsoft_dbdaterec2 {
        DBINT year;		/* 1753 - 9999  	   */
        DBINT quarter;		/* 1 - 4 		   */
        DBINT month;		/* 1 - 12 		   */
        DBINT day;		/* 1 - 31 		   */
        DBINT dayofyear;	/* 1 - 366 		   */
        DBINT week;            	/* 1 - 54 (for leap years) */
        DBINT weekday;		/* 1 - 7 (Mon. - Sun.)     */
        DBINT hour;		/* 0 - 23 		   */
        DBINT minute;		/* 0 - 59 		   */
        DBINT second;		/* 0 - 59 		   */
        DBINT nanosecond;	/* 0 - 999999999	   */
        DBINT tzone;		/* 0 - 127  (Sybase only)  */
    };

    alias tds_microsoft_dbdaterec  DBDATEREC;
    alias tds_microsoft_dbdaterec2 DBDATEREC2;

    RETCODE dbinit();
    void dbexit();

    alias EHANDLEFUNC = int function(DBPROCESS *dbproc, int severity, int dberr, int oserr, char *dberrstr, char *oserrstr);

    alias MHANDLEFUNC = int function(DBPROCESS *dbproc, DBINT msgno, int msgstate, int severity, char *msgtext, char *srvname,
            char *proc, int line);

    void dbsetuserdata(DBPROCESS * dbproc, BYTE * ptr);
    BYTE *dbgetuserdata(DBPROCESS * dbproc);

    EHANDLEFUNC dberrhandle(EHANDLEFUNC handler);
    MHANDLEFUNC dbmsghandle(MHANDLEFUNC handler);

    struct TDSLOGIN;

    struct LOGINREC {
        TDSLOGIN *tds_login;
    };

    LOGINREC *dblogin();
    void dbloginfree(LOGINREC * login);

    RETCODE dbsetlname(LOGINREC * login, const char *value, int which);

    struct DBPROCESS;
    alias tds_dblib_dbprocess = DBPROCESS;

    DBPROCESS *dbopen(LOGINREC * login, const char *server);
    DBPROCESS *tdsdbopen(LOGINREC * login, const char *server, int msdblib);
    void dbclose(DBPROCESS * dbproc);

    RETCODE dbuse(DBPROCESS* dbproc, const char *name);

    // something about array def is a problem
    //RETCODE dbcmd(DBPROCESS * dbproc, const char[] cmdstring);
    RETCODE dbcmd(DBPROCESS * dbproc, const char* cmdstring);

    RETCODE dbsqlexec(DBPROCESS * dbproc);

    RETCODE dbresults(DBPROCESS * dbproc);
    int dbnumcols(DBPROCESS * dbproc);

    char *dbcolname(DBPROCESS * dbproc, int column);
    int dbcoltype(DBPROCESS * dbproc, int column);
    DBINT dbcollen(DBPROCESS * dbproc, int column);

    RETCODE dbbind(DBPROCESS * dbproc, int column, int vartype, DBINT varlen, BYTE * varaddr);
    RETCODE dbnullbind(DBPROCESS * dbproc, int column, DBINT * indicator);

    STATUS dbnextrow(DBPROCESS * dbproc);

    // date functions
    RETCODE dbdatecrack(DBPROCESS * dbproc, DBDATEREC * di, DBDATETIME * dt);
    RETCODE dbanydatecrack(DBPROCESS * dbproc, DBDATEREC2 * di, int type, const void *data);

    // tds functions (from tds.h), not accessible from dblib :)
    alias ubyte TDS_TINYINT;

    void tds_set_packet(TDSLOGIN * tds_login, int packet_size);
    void tds_set_port(TDSLOGIN * tds_login, int port);
    bool tds_set_passwd(TDSLOGIN * tds_login, const char *password);
    void tds_set_bulk(TDSLOGIN * tds_login, TDS_TINYINT enabled);
    bool tds_set_user(TDSLOGIN * tds_login, const char *username);
    bool tds_set_app(TDSLOGIN * tds_login, const char *application);
    bool tds_set_host(TDSLOGIN * tds_login, const char *hostname);
    bool tds_set_library(TDSLOGIN * tds_login, const char *library);
    bool tds_set_server(TDSLOGIN * tds_login, const char *server);
    bool tds_set_client_charset(TDSLOGIN * tds_login, const char *charset);
    bool tds_set_language(TDSLOGIN * tds_login, const char *language);
    void tds_set_version(TDSLOGIN * tds_login, TDS_TINYINT major_ver, TDS_TINYINT minor_ver);
    //int tds_connect_and_login(TDSSOCKET * tds, TDSLOGIN * login);

}


