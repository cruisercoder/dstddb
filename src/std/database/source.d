module std.database.source;

struct Source {
    string type;
    string server;
    string host;
    int port;
    string path; // for file references (sqlite)
    string database;
    string username;
    string password;
}


