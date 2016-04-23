module std.database.mysql.bindings;
import core.stdc.config;

extern(System) {
    struct MYSQL;
    struct MYSQL_RES;
    struct NET;
    /* typedef */ alias const(ubyte)* cstring;
    alias ubyte my_bool;

    enum MYSQL_NO_DATA = 100;
    enum MYSQL_DATA_TRUNCATED = 101;

    //enum enum_field_types
    enum {
        MYSQL_TYPE_DECIMAL,
        MYSQL_TYPE_TINY,
        MYSQL_TYPE_SHORT,
        MYSQL_TYPE_LONG,
        MYSQL_TYPE_FLOAT,
        MYSQL_TYPE_DOUBLE,
        MYSQL_TYPE_NULL, 
        MYSQL_TYPE_TIMESTAMP,
        MYSQL_TYPE_LONGLONG,
        MYSQL_TYPE_INT24,
        MYSQL_TYPE_DATE,
        MYSQL_TYPE_TIME,
        MYSQL_TYPE_DATETIME, 
        MYSQL_TYPE_YEAR,
        MYSQL_TYPE_NEWDATE, 
        MYSQL_TYPE_VARCHAR,
        MYSQL_TYPE_BIT,
        MYSQL_TYPE_TIMESTAMP2,
        MYSQL_TYPE_DATETIME2,
        MYSQL_TYPE_TIME2,
        MYSQL_TYPE_NEWDECIMAL=246,
        MYSQL_TYPE_ENUM=247,
        MYSQL_TYPE_SET=248,
        MYSQL_TYPE_TINY_BLOB=249,
        MYSQL_TYPE_MEDIUM_BLOB=250,
        MYSQL_TYPE_LONG_BLOB=251,
        MYSQL_TYPE_BLOB=252,
        MYSQL_TYPE_VAR_STRING=253,
        MYSQL_TYPE_STRING=254,
        MYSQL_TYPE_GEOMETRY=255
    };


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

        //version(MySQL_51) {
        void* extension;
        //}

        version (webscalesql) {
            /* The position in buff we continue reads from when data is next
             * available */
            ubyte *cur_pos;

            /* Blocking state */
            net_async_block_state async_blocking_state;
        }

    }

    struct MYSQL_BIND {
        c_ulong	*length;          /* output length pointer */
        my_bool       *is_null;	  /* Pointer to null indicator */
        void		*buffer;	  /* buffer to get/put data */
        /* set this if you want to track data truncations happened during fetch */
        my_bool       *error;
        ubyte *row_ptr;         /* for the current data position */
        void function(NET *net, MYSQL_BIND* param) store_param_func;
        void function(MYSQL_BIND*, MYSQL_FIELD *, ubyte **row) fetch_result;
        void function(MYSQL_BIND*, MYSQL_FIELD *, ubyte **row) skip_result;
        /* output buffer length, must be set when fetching str/binary */
        c_ulong buffer_length;
        c_ulong offset;           /* offset position for char/binary fetch */
        c_ulong length_value;     /* Used if length is 0 */
        uint	param_number;	  /* For null count and error messages */
        uint  pack_length;	  /* Internal length for packed data */

        //enum enum_field_types buffer_type;	/* buffer type */
        int buffer_type;

        my_bool       error_value;      /* used if error is 0 */
        my_bool       is_unsigned;      /* set if integer type is unsigned */
        my_bool	long_data_used;	  /* If used with mysql_send_long_data */
        my_bool	is_null_value;    /* Used if is_null is 0 */
        void *extension;
    }

    /* typedef */ alias cstring* MYSQL_ROW;

    const(char *) mysql_get_client_info();

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

    struct MYSQL_STMT;
    MYSQL_STMT* mysql_stmt_init(MYSQL *);
    my_bool mysql_stmt_close(MYSQL_STMT *);
    int mysql_stmt_prepare(MYSQL_STMT *, const char *, ulong);
    const(char *) mysql_stmt_error(MYSQL_STMT *);
    int mysql_stmt_execute(MYSQL_STMT *);

    MYSQL_RES* mysql_stmt_result_metadata(MYSQL_STMT *);

    my_bool mysql_stmt_bind_result(MYSQL_STMT *, MYSQL_BIND *);

    int mysql_stmt_fetch(MYSQL_STMT *);
    c_ulong mysql_stmt_field_count(MYSQL_STMT*);
    c_ulong mysql_stmt_param_count(MYSQL_STMT *);

    my_bool mysql_stmt_bind_param(MYSQL_STMT *, MYSQL_BIND *);

    enum MYSQL_TIMESTAMP_TYPE {
        MYSQL_TIMESTAMP_NONE    = -2,
        MYSQL_TIMESTAMP_ERROR   = -1,
        MYSQL_TIMESTAMP_DATE    =  0,
        MYSQL_TIMESTAMP_DATETIME= 1,
        MYSQL_TIMESTAMP_TIME    = 2
    };

    struct MYSQL_TIME {
        uint  year, month, day, hour, minute, second;
        uint  second_part;
        my_bool neg;
        MYSQL_TIMESTAMP_TYPE time_type;
    };

    version (webscalesql) {

        /* Is the async operation still pending? */
        enum net_async_status_enum {
            NET_ASYNC_COMPLETE = 20100,
            NET_ASYNC_NOT_READY
        };
        alias net_async_status_enum net_async_status;

        /* For an async operation, what we are waiting for, if anything. */
        enum net_async_operation_enum {
            NET_ASYNC_OP_IDLE = 0,
            NET_ASYNC_OP_READING = 20200,
            NET_ASYNC_OP_WRITING,
            NET_ASYNC_OP_COMPLETE
        };
        alias net_async_operation_enum net_async_operation;

        /* Reading a packet is a multi-step process, so we have a state machine. */
        enum net_async_read_packet_state_enum {
            NET_ASYNC_PACKET_READ_IDLE = 0,
            NET_ASYNC_PACKET_READ_HEADER = 20300,
            NET_ASYNC_PACKET_READ_BODY,
            NET_ASYNC_PACKET_READ_COMPLETE
        };
        alias net_async_read_packet_state_enum net_async_read_packet_state;

        /* As is reading a query result. */
        enum net_read_query_result_status_enum {
            NET_ASYNC_READ_QUERY_RESULT_IDLE = 0,
            NET_ASYNC_READ_QUERY_RESULT_FIELD_COUNT = 20240,
            NET_ASYNC_READ_QUERY_RESULT_FIELD_INFO
        };
        alias net_read_query_result_status_enum net_read_query_result_status;

        /* Sending a command involves the write as well as reading the status. */
        enum net_send_command_status_enum {
            NET_ASYNC_SEND_COMMAND_IDLE = 0,
            NET_ASYNC_SEND_COMMAND_WRITE_COMMAND = 20340,
            NET_ASYNC_SEND_COMMAND_READ_STATUS = 20340
        };
        alias net_send_command_status_enum net_send_command_status;

        enum net_async_block_state_enum {
            NET_NONBLOCKING_CONNECT = 20130,
            NET_NONBLOCKING_READ = 20140,
            NET_NONBLOCKING_WRITE = 20150
        };

        alias net_async_block_state_enum net_async_block_state;

        MYSQL* mysql_real_connect_nonblocking_init(
                MYSQL *mysql,
                cstring host,
                cstring user,
                cstring passwd,
                cstring db,
                uint port,
                cstring unix_socket,
                c_ulong clientflag);

        net_async_status mysql_real_connect_nonblocking_run(
                MYSQL *mysql,
                int *error);

        net_async_status mysql_send_query_nonblocking(
                MYSQL* mysql, 
                const char* query, 
                int *error);

        net_async_status mysql_real_query_nonblocking(
                MYSQL *mysql,
                const char* query,
                ulong length,
                int *error);

        net_async_status mysql_next_result_nonblocking(
                MYSQL *mysql,
                int* error);

        net_async_status mysql_select_db_nonblocking(
                MYSQL *mysql,
                const char *db,
                my_bool* error);

        int mysql_get_file_descriptor(MYSQL *mysql);

        net_async_status mysql_free_result_nonblocking(MYSQL_RES *result);

        net_async_status mysql_fetch_row_nonblocking(
                MYSQL_RES *res,
                MYSQL_ROW* row);
    }

}

