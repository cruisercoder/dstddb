module std.database.vibe.test;
import std.database.util;
import std.database.common;
import std.database.postgres;
import std.database.allocator;
import std.stdio;

import std.experimental.logger;

import std.database.postgres.bindings;
import std.socket;

import std.database.vibehandler;
import vibe.core.core;

unittest {
    vibeTest();
}

auto posixSocket(PGconn *c) {
    int r = PQsocket(c);
    if(r == -1) throw new Exception("bad socket value");
    return r;
}

Socket toSocket(int posixSocket) {
    import core.sys.posix.unistd: dup;
    socket_t s = cast(socket_t) dup(cast(socket_t) posixSocket);
    return new Socket(s, AddressFamily.UNSPEC);
}

bool ready(PGconn *c) {
    return PQconnectPoll(c) == PGRES_POLLING_OK;
}

struct MyAsyncPolicy {
    alias Allocator = MyMallocator;
    static const bool nonblocking = true;
    alias Handler = VibeHandler!int;
}


void vibeTest() {
    //import vibe.core.concurrency; // std concurrency conflict
    //import std.socket;
    //import core.sys.posix.sys.select;

    alias DB = Database!MyAsyncPolicy;
    auto db = DB("postgres://127.0.0.1/test");

    auto con = db.connection();
    //auto c = cast(PGconn*) c.handle();

    auto rows = con.query("select name from score").rows;
    rows.writeRows;

/*
    Socket sock = toSocket(posixSocket(con));

    sock.blocking = false;

    VibeHandler!int handler;

    runTask({
            log("a");
            handler.yield();
            log("b");
            });


    runTask({
            log("1");
            handler.yield();
            log("2");
            });

    log("yield");
    yield();
*/

    /*
       auto db = createAsyncDatabase("postgres://127.0.0.1/test");
    //auto con = cast(PGconn*) db.connection().handle(); // why not? possible resource destruct
    auto c = db.connection();
    auto con = cast(PGconn*) c.handle();
     */

    /*
       auto future1 = async({
       log("async1");
       return 1;
       });

       auto future2 = async({
       log("async2");
       return 2;
       });
     */

    // can't join in different threads
    //log("result1: ", future1.getResult);
    //log("result2: ", future2.getResult);

}



/*

//auto stmt = con.query("select name from score");

log("socket: ", socket);

// loop

SocketSet readset, writeset, errorset;
uint setSize = FD_SETSIZE;
log("setSize:", setSize);

readset  = new SocketSet(setSize);
writeset = new SocketSet(setSize);
errorset = new SocketSet(setSize);


// loop until no sockets left
while (true) {
auto socket = PQsocket(con);

readset.reset();
writeset.reset();
errorset.reset();

//socket_t s;
//readset.add(socket);

log("select waiting...");
int events = Socket.select(readset, writeset, errorset);
}

//alias fd_set_type = typeof(fd_set.init.tupleof[0][0]);
//enum FD_NFDBITS = 8 * fd_set_type.sizeof;
//log("FD_NFDBITS: ", FD_NFDBITS);
 */


