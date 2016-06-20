module std.database.oracle.bindings;
import core.stdc.config;

enum OCI_SUCCESS = 0;
enum OCI_SUCCESS_WITH_INFO = 1;
enum OCI_NO_DATA = 100;

enum OCI_ATTR_PREFETCH_ROWS = 13;
enum OCI_ATTR_ROWS_FETCHED = 197;

enum OCI_THREADED = 0x00000001;
enum OCI_OBJECT = 0x00000002;

enum OCI_HTYPE_ENV = 1;
enum OCI_HTYPE_ERROR = 2;
enum OCI_HTYPE_SVCCTX = 3;
enum OCI_HTYPE_STMT = 4;

enum OCI_NTV_SYNTAX = 1;

enum OCI_DEFAULT = 0x00000000;
enum OCI_COMMIT_ON_SUCCESS = 0x00000020;

enum OCI_FETCH_CURRENT = 0x00000001;
enum OCI_FETCH_NEXT = 0x00000002;
enum OCI_FETCH_FIRST = 0x00000004;
enum OCI_FETCH_LAST = 0x00000008;
enum OCI_FETCH_PRIOR = 0x00000010;
enum OCI_FETCH_ABSOLUTE = 0x00000020;
enum OCI_FETCH_RELATIVE = 0x00000040;

enum OCI_ATTR_PARAM_COUNT = 18;
enum OCI_ATTR_STMT_TYPE = 24;
enum OCI_ATTR_BIND_COUNT = 190;

enum OCI_ATTR_DATA_SIZE = 1;
enum OCI_ATTR_DATA_TYPE = 2;
enum OCI_ATTR_DISP_SIZE = 3;
enum OCI_ATTR_NAME = 4;
enum OCI_ATTR_PRECISION = 5;
enum OCI_ATTR_SCALE = 6;
enum OCI_ATTR_IS_NULL = 7;
enum OCI_ATTR_TYPE_NAME = 8;


enum OCI_STMT_UNKNOWN = 0;
enum OCI_STMT_SELECT = 1;
enum OCI_STMT_UPDATE = 2;
enum OCI_STMT_DELETE = 3;
enum OCI_STMT_INSERT = 4;
enum OCI_STMT_CREATE = 5;
enum OCI_STMT_DROP = 6;
enum OCI_STMT_ALTER = 7;
enum OCI_STMT_BEGIN = 8;
enum OCI_STMT_DECLARE = 9;
enum OCI_STMT_CALL = 10;

enum OCI_DTYPE_PARAM = 53;

// from ocidfn.h

enum SQLT_CHR = 1;                        /* (ORANET TYPE) character string */
enum SQLT_NUM = 2;                          /* (ORANET TYPE) oracle numeric */
enum SQLT_INT = 3;                                 /* (ORANET TYPE) integer */
enum SQLT_FLT = 4;                   /* (ORANET TYPE) Floating point number */
enum SQLT_STR = 5;                                /* zero terminated string */
enum SQLT_VNU = 6;                        /* NUM with preceding length byte */
enum SQLT_PDN = 7;                  /* (ORANET TYPE) Packed Decimal Numeric */
enum SQLT_LNG = 8;                                                  /* long */
enum SQLT_VCS = 9;                             /* Variable character string */
enum SQLT_NON = 10;                      /* Null/empty PCC Descriptor entry */
enum SQLT_RID = 11;                                                /* rowid */
enum SQLT_DAT = 12;                                /* date in oracle format */
enum SQLT_VBI = 15;                                 /* binary in VCS format */
enum SQLT_BFLOAT = 21;                                /* Native Binary float*/
enum SQLT_BDOUBLE = 22;                             /* NAtive binary double */
enum SQLT_BIN = 23;                                  /* binary data(DTYBIN) */
enum SQLT_LBI = 24;                                          /* long binary */
enum SQLT_UIN = 68;                                     /* unsigned integer */
enum SQLT_SLS = 91;                        /* Display sign leading separate */
enum SQLT_LVC = 94;                                  /* Longer longs (char) */
enum SQLT_LVB = 95;                                   /* Longer long binary */
enum SQLT_AFC = 96;                                      /* Ansi fixed char */
enum SQLT_AVC = 97;                                        /* Ansi Var char */
enum SQLT_IBFLOAT = 100;                          /* binary float canonical */
enum SQLT_IBDOUBLE = 101;                         /* binary double canonical */
enum SQLT_CUR = 102;                                        /* cursor  type */
enum SQLT_RDD = 104;                                    /* rowid descriptor */
enum SQLT_LAB = 105;                                          /* label type */
enum SQLT_OSL = 106;                                        /* oslabel type */

enum SQLT_NTY = 108;                                   /* named object type */
enum SQLT_REF = 110;                                            /* ref type */
enum SQLT_CLOB= 112;                                       /* character lob */
enum SQLT_BLOB = 113;                                          /* binary lob */
enum SQLT_BFILEE = 114;                                   /* binary file lob */
enum SQLT_CFILEE = 115;                                /* character file lob */
enum SQLT_RSET = 116;                                     /* result set type */
enum SQLT_NCO = 122;      /* named collection type (varray or nested table) */
enum SQLT_VST =  155;                                      /* OCIString type */
enum SQLT_ODT = 156;                                        /* OCIDate type */

extern(System) {
    /* typedef */ alias void* dvoid;
    /* typedef */ alias int sword;
    /* typedef */ alias ubyte ub1;
    /* typedef */ alias ushort ub2;
    /* typedef */ alias short sb2;
    /* typedef */ alias uint ub4;
    /* typedef */ alias int sb4;

    alias ubyte OraText;

    struct OCIEnv;
    struct OCIError;
    struct OCISvcCtx;
    struct OCIStmt;
    struct OCISnapshot;
    struct OCIParam;
    struct OCIDefine;
    struct OCIDateTime;

    sword OCIEnvCreate (
            OCIEnv **envhpp,
            ub4 mode,
            const dvoid *ctxp,
            void* function(void  *ctxp, size_t size) malocfp,
            void* function(void  *ctxp, void  *memptr, size_t newsize) ralocfp,
            void function(void  *ctxp, void  *memptr) mfreefp,
            size_t xtramem_sz,
            void** usrmempp );

    sword OCIHandleAlloc(const void  *parenth, void  **hndlpp, const ub4 type, 
            const size_t xtramem_sz, void  **usrmempp);

    sword OCIHandleFree(void *hndlp, const ub4 type);

    sword OCILogon (OCIEnv *envhp, OCIError *errhp, OCISvcCtx **svchp, 
            const OraText *username, ub4 uname_len, 
            const OraText *password, ub4 passwd_len, 
            const OraText *dbname, ub4 dbname_len);

    sword OCILogoff (OCISvcCtx *svchp, OCIError *errhp);

    sword OCIStmtPrepare (OCIStmt *stmtp, OCIError *errhp, const OraText *stmt,
            ub4 stmt_len, ub4 language, ub4 mode);

    sword OCIStmtExecute (OCISvcCtx *svchp, OCIStmt *stmtp, OCIError *errhp, 
            ub4 iters, ub4 rowoff, const OCISnapshot *snap_in, 
            OCISnapshot *snap_out, ub4 mode);

    sword OCIStmtFetch2 (OCIStmt *stmtp, OCIError *errhp, ub4 nrows, 
            ub2 orientation, sb4 scrollOffset, ub4 mode);

    sword OCIAttrGet (const void  *trgthndlp, ub4 trghndltyp, 
            void  *attributep, ub4 *sizep, ub4 attrtype, 
            OCIError *errhp);

    sword OCIAttrSet (void  *trgthndlp, ub4 trghndltyp, void  *attributep,
                    ub4 size, ub4 attrtype, OCIError *errhp);

    sword OCIParamGet (const void  *hndlp, ub4 htype, OCIError *errhp, 
            void  **parmdpp, ub4 pos);

    sword OCIDefineByPos (OCIStmt *stmtp, OCIDefine **defnp, OCIError *errhp,
            ub4 position, void  *valuep, sb4 value_sz, ub2 dty,
            void  *indp, ub2 *rlenp, ub2 *rcodep, ub4 mode);

    sword OCIDefineArrayOfStruct(
            OCIDefine *defnp,
            OCIError *errhp,
            ub4 pvskip,
            ub4 indskip,
            ub4 rlskip,
            ub4 rcskip);

    sword OCIDateTimeGetDate(void *hndl, OCIError *err,  const OCIDateTime *date,
            sb2 *year, ub1 *month, ub1 *day );

    // from orl.h

    struct OCITime {
        ub1 OCITimeHH;                          /* hours; range is 0 <= hours <=23 */
        ub1 OCITimeMI;                     /* minutes; range is 0 <= minutes <= 59 */
        ub1 OCITimeSS;                     /* seconds; range is 0 <= seconds <= 59 */
    }

    struct OCIDate {
        sb2 OCIDateYYYY;         /* gregorian year; range is -4712 <= year <= 9999 */
        ub1 OCIDateMM;                          /* month; range is 1 <= month < 12 */
        ub1 OCIDateDD;                             /* day; range is 1 <= day <= 31 */
        OCITime OCIDateTime;                                               /* time */
    }

}

