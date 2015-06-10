module std.database.mysql.bindings;
import core.stdc.config;


extern(System) {
    struct MYSQL;
    struct MYSQL_RES;
    /* typedef */ alias const(ubyte)* cstring;

    struct MYSQL_FIELD {
        cstring name;                 /* Name of column */
        cstring org_name;             /* Original column name, if an alias */ 
        cstring table;                /* Table of column if column was a field */
        cstring org_table;            /* Org table name, if table was an alias */
        cstring db;                   /* Database for table */
        cstring catalog;        /* Catalog for table */
        cstring def;                  /* Default value (set by mysql_list_fields) */
        c_ulong length;       /* Width of column (create length) */
        c_ulong max_length;   /* Max width for selected set */
        uint name_length;
        uint org_name_length;
        uint table_length;
        uint org_table_length;
        uint db_length;
        uint catalog_length;
        uint def_length;
        uint flags;         /* Div flags */
        uint decimals;      /* Number of decimals in field */
        uint charsetnr;     /* Character set */
        uint type; /* Type of field. See mysql_com.h for types */
        // type is actually an enum btw

        version(MySQL_51) {
            void* extension;
        }
    }

    /* typedef */ alias cstring* MYSQL_ROW;

    cstring mysql_get_client_info();
    MYSQL* mysql_init(MYSQL*);
    uint mysql_errno(MYSQL*);
    cstring mysql_error(MYSQL*);

    MYSQL* mysql_real_connect(MYSQL*, cstring, cstring, cstring, cstring, uint, cstring, c_ulong);

    int mysql_query(MYSQL*, cstring);

    void mysql_close(MYSQL*);

    ulong mysql_num_rows(MYSQL_RES*);
    uint mysql_num_fields(MYSQL_RES*);
    bool mysql_eof(MYSQL_RES*);

    ulong mysql_affected_rows(MYSQL*);
    ulong mysql_insert_id(MYSQL*);

    MYSQL_RES* mysql_store_result(MYSQL*);
    MYSQL_RES* mysql_use_result(MYSQL*);

    MYSQL_ROW mysql_fetch_row(MYSQL_RES *);
    c_ulong* mysql_fetch_lengths(MYSQL_RES*);
    MYSQL_FIELD* mysql_fetch_field(MYSQL_RES*);
    MYSQL_FIELD* mysql_fetch_fields(MYSQL_RES*);

    uint mysql_real_escape_string(MYSQL*, ubyte* to, cstring from, c_ulong length);

    void mysql_free_result(MYSQL_RES*);
}

