module std.database.oracle.bindings;
import core.stdc.config;

enum
OCI_THREADED = 0x00000001,
             OCI_OBJECT = 0x00000002;

enum
OCI_HTYPE_ENV = 1;

extern(System) {
    /* typedef */ alias void* dvoid;
    /* typedef */ alias int sword;
    /* typedef */ alias uint ub4;
    /* typedef */ alias int sb4;

    struct OCIEnv;

    sword OCIEnvCreate (
            OCIEnv **envhpp,
            ub4 mode,
            const dvoid *ctxp,
            //const dvoid *(*malocfp) (dvoid *ctxp, size_t size),
            //const dvoid *(*ralocfp) (dvoid *ctxp, dvoid *memptr, size_t newsize),
            //const void (*mfreefp) (dvoid *ctxp, dvoid *memptr)) size_t xtramemsz,
          const dvoid *,
          const dvoid *,
          const dvoid *,
          dvoid **usrmempp );

    sword OCIHandleFree(void *hndlp, const ub4 type);
}


