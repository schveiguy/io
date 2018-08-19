/**
   Synchronous driver for std.io

   License: $(HTTP boost.org/LICENSE_1_0.txt, Boost License 1.0).
   Authors: Martin Nowak
   Source: $(PHOBOSSRC std/io/driver/_sync.d)
*/
module std.io.driver.sync;

import std.io.driver;
import std.io.exception : enforce;
import std.io.internal.string;

version (Posix)
{
    import core.sys.posix.fcntl;
    import core.sys.posix.netinet.in_;
    import core.sys.posix.sys.socket;
    import core.sys.posix.sys.uio : readv, writev;
    import core.sys.posix.unistd : close, read, write, lseek;
    import std.io.internal.iovec : tempIOVecs;

    enum O_BINARY = 0;
}
else version (Windows)
{
    import core.stdc.stdio : O_RDONLY, O_WRONLY, O_RDWR, O_APPEND, O_CREAT,
        O_TRUNC, O_BINARY;
    import core.sys.windows.winbase;
    import core.sys.windows.windef;
    import core.sys.windows.winsock2;

    extern (Windows)
    {
    nothrow @nogc:
        struct WSABUF
        {
            ULONG len;
            CHAR* buf;
        }

        alias WSABUF* LPWSABUF;

        int WSASend(SOCKET s, LPWSABUF lpBuffers, DWORD dwBufferCount, LPDWORD lpNumberOfBytesSent, DWORD dwFlags,
                LPWSAOVERLAPPED lpOverlapped, LPWSAOVERLAPPED_COMPLETION_ROUTINE lpCompletionRoutine);
        int WSARecv(SOCKET s, LPWSABUF lpBuffers, DWORD dwBufferCount, LPDWORD lpNumberOfBytesRecvd, LPDWORD lpFlags,
                LPWSAOVERLAPPED lpOverlapped, LPWSAOVERLAPPED_COMPLETION_ROUTINE lpCompletionRoutine);
        int WSARecvFrom(SOCKET s, LPWSABUF lpBuffers, DWORD dwBufferCount,
                LPDWORD lpNumberOfBytesRecvd, LPDWORD lpFlags, sockaddr* lpFrom,
                LPINT lpFromlen, LPWSAOVERLAPPED lpOverlapped,
                LPWSAOVERLAPPED_COMPLETION_ROUTINE lpCompletionRoutine);
        int WSASendTo(SOCKET s, LPWSABUF lpBuffers, DWORD dwBufferCount,
                LPDWORD lpNumberOfBytesSent, DWORD dwFlags, in sockaddr* lpTo,
                int iTolen, LPWSAOVERLAPPED lpOverlapped,
                LPWSAOVERLAPPED_COMPLETION_ROUTINE lpCompletionRoutine);
    }
}
else
    static assert(0, "unimplemented");

/**
   Synchronous driver implementation.

   This driver uses the default platform APIs for synchronous I/O.
*/
class SyncDriver : Driver
{
shared @safe @nogc:

    //==============================================================================
    // files
    //==============================================================================

    override FILE createFile( /*in*/ const scope tchar[] path, Mode mode) @trusted
    {
        version (Posix)
        {
            auto fd = .open(path.ptr, mode, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH);
        }
        else version (Windows)
            auto fd = .CreateFileW(path.ptr, accessMask(mode), shareMode(mode),
                    null, creationDisposition(mode), FILE_ATTRIBUTE_NORMAL, null);
        else
            static assert(0, "unimplemented");
        enforce(fd != INVALID_HANDLE_VALUE, {
            auto s = String("opening ");
            s ~= path;
            s ~= " failed";
            return s.move;
        });
        return h2f(fd);
    }

    version (Posix)
        override FILE fileFromHandle(int fd)
    {
        return h2f(fd);
    }
    else version (Windows)
        override FILE fileFromHandle(HANDLE fd)
    {
        return h2f(fd);
    }
    else
        static assert(0, "unimplemented");

    override void closeFile(scope FILE f) @trusted
    {
        version (Posix)
            enforce(!.close(f2h(f)), "close failed".String);
        else
            enforce(CloseHandle(f2h(f)), "close failed".String);
    }

    override size_t read(scope FILE f, scope ubyte[] buf) @trusted
    {
        version (Posix)
        {
            immutable ret = .read(f2h(f), buf.ptr, buf.length);
            enforce(ret != -1, "read failed".String);
            return ret;
        }
        else version (Windows)
        {
            assert(buf.length <= uint.max);
            DWORD n;
            immutable ret = ReadFile(f2h(f), buf.ptr, cast(uint) buf.length, &n, null);
            enforce(ret, "read failed".String);
            return n;
        }
    }

    override size_t read(scope FILE f, scope ubyte[][] bufs) @trusted
    {
        version (Posix)
        {
            auto vecs = tempIOVecs(bufs);
            immutable ret = .readv(f2h(f), vecs.ptr, cast(int) vecs.length);
            enforce(ret != -1, "read failed".String);
            return ret;
        }
        else
        {
            size_t total;
            foreach (b; bufs)
            {
                immutable len = read(f, b);
                total += len;
                if (len < b.length)
                    break;
            }
            return total;
        }
    }

    override size_t write(scope FILE f, /*in*/ const scope ubyte[] buf) @trusted
    {
        version (Posix)
        {
            immutable ret = .write(f2h(f), buf.ptr, buf.length);
            enforce(ret != -1, "write failed".String);
            return ret;
        }
        else version (Windows)
        {
            assert(buf.length <= uint.max);
            DWORD n;
            immutable ret = WriteFile(f2h(f), buf.ptr, cast(uint) buf.length, &n, null);
            enforce(ret, "write failed".String);
            return n;
        }
    }

    override size_t write(scope FILE f, /*in*/ const scope ubyte[][] bufs) @trusted
    {
        version (Posix)
        {
            auto vecs = tempIOVecs(bufs);
            immutable ret = .writev(f2h(f), vecs.ptr, cast(int) vecs.length);
            enforce(ret != -1, "write failed".String);
            return ret;
        }
        else
        {
            size_t total;
            foreach (b; bufs)
            {
                immutable len = write(f, b);
                total += len;
                if (len < b.length)
                    break;
            }
            return total;
        }
    }

    override ulong seek(scope FILE f, long offset, int whence) @trusted
    {
        version (Posix)
        {
            immutable ret = .lseek(f2h(f), offset, whence);
            enforce(ret != -1, "seek failed".String);
            return ret;
        }
        else version (Windows)
        {
            LARGE_INTEGER off = void;
            off.QuadPart = offset;
            LARGE_INTEGER npos;
            immutable ret = SetFilePointerEx(f2h(f), off, &npos, whence);
            enforce(ret != 0, "seek failed".String);
            return npos.QuadPart;
        }
    }

    //==============================================================================
    // sockets
    //==============================================================================

    override SOCKET createSocket(AddrFamily family, SocketType type, Protocol protocol)
    {
        version (Windows)
            initWSA();
        auto fd = () @trusted{ return socket(family, type, protocol); }();
        enforce(fd != .INVALID_SOCKET, "creating socket Failed".String);
        return h2s(fd);
    }

    version (Posix)
        override SOCKET socketFromHandle(int fd)
    {
        return h2s(fd);
    }
    else version (Windows)
        override SOCKET socketFromHandle(ws2.SOCKET fd)
    {
        return h2s(fd);
    }
    else
        static assert(0, "unimplemented");

    override void closeSocket(scope SOCKET s) @trusted
    {
        version (Posix)
            enforce(.close(s2h(s)) != -1, "close failed".String);
        else
            enforce(.closesocket(s2h(s)) != SOCKET_ERROR, "close failed".String);
    }

    override void bind(scope SOCKET s, const scope sockaddr* addr, socklen_t addrlen) @system
    {
        enforce(.bind(s2h(s), addr, addrlen) != -1, "bind failed".String);
    }

    override void connect(scope SOCKET s, const scope sockaddr* addr, socklen_t addrlen) @system
    {
        enforce(.connect(s2h(s), addr, addrlen) != -1, "connect failed".String);
    }

    override void listen(scope SOCKET s, uint backlog)
    {
        auto fd = s2h(s);
        immutable res = () @trusted{ return .listen(fd, backlog); }();
        enforce(res != -1, "listen failed".String);
    }

    override SOCKET accept(scope SOCKET s, scope sockaddr* addr, ref socklen_t addrlen) @system
    {
        immutable fd = .accept(s2h(s), addr, &addrlen);
        enforce(fd != -1, "accept failed".String);
        return h2s(fd);
    }

    override void localAddr( /*in*/ const scope SOCKET s, scope sockaddr* addr, ref socklen_t addrlen) @system
    {
        immutable rc = .getsockname(s2h(s), addr, &addrlen);
        enforce(rc != -1, "getsockname failed".String);
    }

    override void setSocketOption(scope SOCKET s, SocketOption option, /*in*/ const scope void* opt,
            uint optlen) @system
    {
        immutable res = .setsockopt(s2h(s), SOL_SOCKET, option, opt, optlen); // TODO: SOL_SOCKET vs. Protocol
        enforce(res != -1, "setsockopt failed".String);
    }

    override void getSocketOption( /*in*/ const scope SOCKET s, SocketOption option,
            scope void* opt, socklen_t optlen) @system
    {
        socklen_t len = optlen;
        immutable res = .getsockopt(s2h(s), SOL_SOCKET, option, opt, &len); // TODO: SOL_SOCKET vs. Protocol
        assert(len == optlen);
        enforce(res != -1, "getsockopt failed".String);
    }

    override size_t recvFrom(scope SOCKET s, scope ubyte[] buf,
            scope sockaddr* addr, ref socklen_t addrlen) @system
    {
        version (Posix)
        {
            immutable n = .recvfrom(s2h(s), buf.ptr, buf.length, 0, addr, &addrlen);
            enforce(n != -1, "Failed to receive from socket.".String);
        }
        else version (Windows)
        {
            DWORD n = void, flags;
            immutable res = .WSARecvFrom(s2h(s), cast(WSABUF*)&buf, 1, &n,
                    &flags, addr, &addrlen, null, null);
            enforce(res == 0, "recv failed".String);
        }
        return n;
    }

    override size_t recvFrom(scope SOCKET s, scope ubyte[][] bufs,
            scope sockaddr* addr, ref socklen_t addrlen) @system
    {
        version (Posix)
        {
            auto vecs = tempIOVecs(bufs);
            msghdr msg = void;
            msg.msg_name = addr;
            msg.msg_namelen = addrlen;
            msg.msg_iov = vecs.ptr;
            msg.msg_iovlen = cast(int)vecs.length;
            msg.msg_control = null;
            msg.msg_controllen = 0;
            msg.msg_flags = 0;
            immutable flags = 0;
            immutable n = .recvmsg(s2h(s), &msg, flags);
            addrlen = msg.msg_namelen;
            enforce(n != -1, "read failed".String);
        }
        else version (Windows)
        {
            DWORD n = void, flags;
            immutable res = .WSARecvFrom(s2h(s), cast(WSABUF*) bufs.ptr,
                    cast(uint) bufs.length, &n, &flags, addr, &addrlen, null, null);
            enforce(res == 0, "recv failed".String);
        }
        return n;
    }

    override size_t sendTo(scope SOCKET s, /*in*/ const scope ubyte[] buf,
            const scope sockaddr* addr, socklen_t addrlen) @system
    {
        version (Posix)
        {
            immutable flags = 0;
            immutable ret = .sendto(s2h(s), buf.ptr, buf.length, flags, addr, addrlen);
            enforce(ret != -1, "sendTo failed".String);
            return ret;
        }
        else version (Windows)
        {
            DWORD n = void, flags;
            immutable res = .WSASendTo(s2h(s), cast(WSABUF*)&buf, 1, &n,
                    flags, addr, addrlen, null, null);
            enforce(!res, "sendTo failed".String);
            return n;
        }
    }

    override size_t sendTo(scope SOCKET s, /*in*/ const scope ubyte[][] bufs,
            const scope sockaddr* addr, socklen_t addrlen) @system
    {
        version (Posix)
        {
            auto vecs = tempIOVecs(bufs);
            msghdr msg = void;
            msg.msg_name = cast(void*) addr;
            msg.msg_namelen = addrlen;
            msg.msg_iov = vecs.ptr;
            msg.msg_iovlen = cast(int)vecs.length;
            msg.msg_control = null;
            msg.msg_controllen = 0;
            msg.msg_flags = 0;
            immutable flags = 0;
            immutable n = .sendmsg(s2h(s), &msg, flags);
            enforce(n != -1, "sendTo failed".String);
        }
        else version (Windows)
        {
            DWORD n = void, flags;
            immutable res = .WSASendTo(s2h(s), cast(WSABUF*) bufs.ptr,
                    cast(uint) bufs.length, &n, flags, addr, addrlen, null, null);
            enforce(!res, "sendTo failed".String);
        }
        return n;
    }

    override size_t recv(scope SOCKET s, scope ubyte[] buf) @trusted
    {
        version (Posix)
        {
            immutable flags = 0;
            immutable n = .recv(s2h(s), buf.ptr, buf.length, flags);
            enforce(n != -1, "recv failed".String);
        }
        else version (Windows)
        {
            DWORD n = void, flags;
            immutable ret = .WSARecv(s2h(s), cast(WSABUF*)&buf, 1, &n, &flags, null, null);
            enforce(ret == 0, "WSARecv failed".String);
        }
        return n;
    }

    override size_t recv(scope SOCKET s, scope ubyte[][] bufs) @trusted
    {
        version (Posix)
        {
            auto vecs = tempIOVecs(bufs);
            immutable n = .readv(s2h(s), vecs.ptr, cast(int) vecs.length);
            enforce(n != -1, "recv failed".String);
        }
        else version (Windows)
        {
            DWORD n = void, flags;
            immutable ret = .WSARecv(s2h(s), cast(WSABUF*) bufs.ptr,
                    cast(uint) bufs.length, &n, &flags, null, null);
            enforce(ret == 0, "WSARecv failed".String);
        }
        return n;
    }

    override size_t send(scope SOCKET s, /*in*/ const scope ubyte[] buf) @trusted
    {
        version (Posix)
        {
            immutable n = .send(s2h(s), buf.ptr, buf.length, 0);
            enforce(n != -1, "send failed".String);
        }
        else version (Windows)
        {
            DWORD n = void, flags;
            immutable ret = .WSASend(s2h(s), cast(WSABUF*)&buf, 1, &n, flags, null, null);
            enforce(ret == 0, "send failed".String);
        }
        return n;
    }

    override size_t send(scope SOCKET s, /*in*/ const scope ubyte[][] bufs) @trusted
    {
        version (Posix)
        {
            auto vecs = tempIOVecs(bufs);
            immutable n = .writev(s2h(s), vecs.ptr, cast(int) vecs.length);
            enforce(n != -1, "send failed".String);
        }
        else version (Windows)
        {
            DWORD n = void, flags;
            immutable ret = .WSASend(s2h(s), cast(WSABUF*) bufs.ptr,
                    cast(uint) bufs.length, &n, flags, null, null);
            enforce(ret == 0, "send failed".String);
        }
        return n;
    }

    //==============================================================================
    // DNS
    //==============================================================================

    int resolve( /*in*/ const scope char[] hostname, /*in*/ const scope char[] service, AddrFamily family,
            SocketType socktype, Protocol protocol,
            scope int delegate(const scope ref AddrInfo ai) @safe @nogc cb) @trusted
    {
        version (Posix)
            import core.sys.posix.netdb;
        else version (Windows)
            import core.sys.windows.winsock2;
        else
            static assert(0, "unimplemented");
        import std.io.net.dns : DNSException;

        version (Windows)
            initWSA();

        addrinfo hints = void;
        with (hints)
        {
            version (Posix)
                ai_flags = AI_V4MAPPED | AI_ADDRCONFIG;
            else
                ai_flags = AI_ADDRCONFIG;
            ai_family = family;
            ai_socktype = socktype;
            ai_protocol = protocol;
            ai_addrlen = 0;
            ai_canonname = null;
            ai_addr = null;
            ai_next = null;
        }
        addrinfo* pai;
        immutable ret = getaddrinfo(hostname.ptr, service.ptr, &hints, &pai);
        enforce!DNSException(ret == 0, {
            auto s = String("failed to resolve '");
            s ~= hostname;
            s ~= ':';
            s ~= service;
            s ~= '\'';
            return s.move;
        }, ret);
        scope (exit)
            freeaddrinfo(pai);
        for (; pai; pai = pai.ai_next)
        {
            static assert(AddrInfo.sizeof == addrinfo.sizeof);
            if (auto r = cb(*cast(const AddrInfo*) pai))
                return r;
        }
        return 0;
    }
}

private:

version (Posix)
{
    enum int INVALID_HANDLE_VALUE = -1;
    enum int INVALID_SOCKET = -1;

    static assert(int.sizeof <= Driver.FILE.sizeof);

    /// handle to file
    Driver.FILE h2f(return scope int fd) pure nothrow @trusted @nogc
    {
        return cast(void*) fd;
    }

    /// file to handle
    int f2h(scope Driver.FILE f) pure nothrow @trusted @nogc
    {
        return cast(int) f;
    }

    static assert(int.sizeof <= Driver.SOCKET.sizeof);

    /// handle to socket
    Driver.SOCKET h2s(return scope int fd) pure nothrow @trusted @nogc
    {
        return cast(Driver.SOCKET) fd;
    }

    /// socket to handle
    inout(int) s2h(scope inout Driver.SOCKET s) pure nothrow @trusted @nogc
    {
        return cast(int) s;
    }
}
else version (Windows)
{
    static import ws2 = core.sys.windows.winsock2;

    static assert(HANDLE.sizeof <= Driver.FILE.sizeof);

    /// handle to file
    Driver.FILE h2f(return scope HANDLE fd) pure nothrow @trusted @nogc
    {
        return cast(Driver.FILE) fd;
    }

    /// file to handle
    HANDLE f2h(return scope Driver.FILE f) pure nothrow @trusted @nogc
    {
        return cast(HANDLE) f;
    }

    static assert(ws2.SOCKET.sizeof <= Driver.SOCKET.sizeof);

    /// handle to socket
    Driver.SOCKET h2s(return scope ws2.SOCKET fd) pure nothrow @trusted @nogc
    {
        return cast(Driver.SOCKET) fd;
    }

    /// socket to handle
    inout(ws2.SOCKET) s2h(scope inout Driver.SOCKET s) pure nothrow @trusted @nogc
    {
        return cast(ws2.SOCKET) s;
    }
}

version (Windows)
{
@safe @nogc:
    DWORD accessMask(Mode mode)
    {
        switch (mode & (Mode.read | Mode.write | Mode.readWrite | Mode.append))
        {
        case Mode.read:
            return GENERIC_READ;
        case Mode.write:
            return GENERIC_WRITE;
        case Mode.readWrite:
            return GENERIC_READ | GENERIC_WRITE;
        case Mode.write | Mode.append:
            return FILE_GENERIC_WRITE & ~FILE_WRITE_DATA;
        case Mode.readWrite | Mode.append:
            return GENERIC_READ | (FILE_GENERIC_WRITE & ~FILE_WRITE_DATA);
        default:
            enforce(0, "invalid mode for access mask".String);
            assert(0);
        }
    }

    DWORD shareMode(Mode mode) pure nothrow
    {
        // do not lock files
        return FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE;
    }

    DWORD creationDisposition(Mode mode) pure nothrow
    {
        switch (mode & (Mode.create | Mode.truncate))
        {
        case cast(Mode) 0:
            return OPEN_EXISTING;
        case Mode.create:
            return OPEN_ALWAYS;
        case Mode.truncate:
            return TRUNCATE_EXISTING;
        case Mode.create | Mode.truncate:
            return CREATE_ALWAYS;
        default:
            assert(0);
        }
    }

    void initWSA() @nogc
    {
        import core.atomic;
        import core.stdc.stdlib : atexit;

        static shared bool initialized;
        if (!atomicLoad!(MemoryOrder.raw)(initialized))
        {
            WSADATA wd;
            immutable res = () @trusted{ return WSAStartup(0x2020, &wd); }();
            enforce(!res, "WSAStartup failed".String);
            static extern (C) void cleanup()
            {
                WSACleanup();
            }

            if (cas(&initialized, false, true))
                () @trusted{ atexit(&cleanup); }();
        }
    }
}
