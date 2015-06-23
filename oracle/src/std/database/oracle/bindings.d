module std.database.oracle.bindings;
import core.stdc.config;


enum OCI_SUCCESS = 0;

enum OCI_THREADED = 0x00000001;
enum OCI_OBJECT = 0x00000002;

enum OCI_HTYPE_ENV = 1;
enum OCI_HTYPE_ERROR = 2;

extern(System) {
    /* typedef */ alias void* dvoid;
    /* typedef */ alias int sword;
    /* typedef */ alias uint ub4;
    /* typedef */ alias int sb4;

    struct OCIEnv;
    struct OCIError;

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
}


