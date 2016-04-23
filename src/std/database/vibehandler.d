module std.database.vibehandler;
import std.socket;


struct VibeHandler(T) {
    import core.time: Duration, dur;
    import vibe.core.core;

    alias Event = FileDescriptorEvent; 
    Duration timeout = dur!"seconds"(10);
    Event event;

    // both for posix sockets

    void addSocket(int sock) {
        event = createFileDescriptorEvent(sock, FileDescriptorEvent.Trigger.any); 
    }

    void addSocket(Socket sock) {addSocket(sock.handle);}

    void wait() {
        //event.wait(timeout);
        //event.wait(FileDescriptorEvent.Trigger.read);
        event.wait(FileDescriptorEvent.Trigger.read);
    }

    void yield() {
        import vibe.core.core: yield;
        yield();
    }
}

