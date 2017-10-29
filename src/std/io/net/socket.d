/**
   Low-level sockets

   License: $(HTTP boost.org/LICENSE_1_0.txt, Boost License 1.0).
   Authors: Martin Nowak
   Source: $(PHOBOSSRC std/io/net/_socket.d)
*/
module std.io.net.socket;

import std.io.net.addr;
import std.io.exception : enforce;
import std.io.internal.string;

version (Posix)
{
    import core.sys.posix.fcntl;
    import core.sys.posix.netinet.in_;
    import core.sys.posix.sys.socket;
    import core.sys.posix.sys.uio : readv, writev;
    import core.sys.posix.unistd : close, read, write;
    import std.io.internal.iovec : tempIOVecs;
}
else version (Windows)
{
    import core.sys.windows.winsock2;
    import core.sys.windows.windef;

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

/// protocol family
alias ProtocolFamily = AddrFamily;

/**
   The socket type specifies the communication semantics.

See_also: http://pubs.opengroup.org/onlinepubs/9699919799/functions/socket.html
 */
enum SocketType
{
    unspecified = 0, // unspecified socket type, mostly as resolve hint
    stream = SOCK_STREAM, // sequenced, reliable, two-way, connection-based data streams
    dgram = SOCK_DGRAM, // unordered, unreliable datagrams of fixed length
    seqpacket = SOCK_SEQPACKET, // sequenced, reliable, two-way datagrams of fixed length
    raw = SOCK_RAW, // raw network access
}

/**
   The socket protocol to use.

See_also: https://www.iana.org/assignments/protocol-numbers
 */
enum Protocol
{
    default_ = 0, /// use default protocol for protocol family and socket type
    ip = IPPROTO_IP, ///
    icmp = IPPROTO_ICMP, ///
    igmp = IPPROTO_IGMP, ///
    ggp = IPPROTO_GGP, ///
    tcp = IPPROTO_TCP, ///
    pup = IPPROTO_PUP, ///
    udp = IPPROTO_UDP,
    idp = IPPROTO_IDP,
    nd = IPPROTO_ND,
}

/**
   Socket options.
 */
enum SocketOption
{
    acceptConn = SO_ACCEPTCONN, /// get whether socket is accepting connections
    broadcast = SO_BROADCAST, /// broadcast for datagram sockets
    debug_ = SO_DEBUG, /// enable socket debugging
    dontRoute = SO_DONTROUTE, /// send only to directly connected hosts
    error = SO_ERROR, /// get pending socket errors
    keepAlive = SO_KEEPALIVE, /// enable keep-alive messages on connection-based sockets
    linger = SO_LINGER, /// linger option
    oobinline = SO_OOBINLINE, /// inline receive out-of-band data
    rcvbuf = SO_RCVBUF, /// get or set receive buffer size
    rcvlowat = SO_RCVLOWAT, /// min number of input bytes to process
    rcvtimeo = SO_RCVTIMEO, /// receiving timeout
    reuseAddr = SO_REUSEADDR, /// reuse bind address
    sndbuf = SO_SNDBUF, /// get or set send buffer size
    sndlowat = SO_SNDLOWAT, /// min number of output bytes to process
    sndtimeo = SO_SNDTIMEO, /// sending timeout
    type = SO_TYPE, /// get socket type
}

/// option value types for SocketOption
alias SocketOptionType(SocketOption opt) = int;
/// ditto
alias SocketOptionType(SocketOption opt : SocketOption.linger) = linger;
/// ditto
alias SocketOptionType(SocketOption opt : SocketOption.rcvtimeo) = timeval;
/// ditto
alias SocketOptionType(SocketOption opt : SocketOption.sndtimeo) = timeval;

/**
   A socket
 */
struct Socket
{
@nogc @safe:
    /**
       Construct socket for protocol `family`, socket `type`, and `protocol`.
     */
    this(ProtocolFamily family, SocketType type, Protocol protocol = Protocol.default_) @trusted
    {
        version (Windows)
            initWSA();
        fd = socket(family, type, protocol);
        enforce(fd != INVALID_SOCKET, "creating socket Failed".String);
    }

    /// take ownership of an existing socket `handle`
    version (Posix)
        this(int handle) pure nothrow
    {
        this.fd = handle;
    }
    else version (Windows)
        this(SOCKET handle) pure nothrow
    {
        this.fd = handle;
    }

    ///
    ~this()
    {
        close();
    }

    /// close the socket
    void close() @trusted
    {
        if (fd == INVALID_SOCKET)
            return;
        version (Posix)
            enforce(.close(fd) != -1, "close failed".String);
        else
            enforce(.closesocket(fd) != SOCKET_ERROR, "close failed".String);
        fd = INVALID_SOCKET;
    }

    /// return whether the socket is open
    bool isOpen() const pure nothrow
    {
        return fd != INVALID_SOCKET;
    }

    /**
       Bind socket to `addr`.

       Params:
         addr = socket address to bind

       See_also: http://pubs.opengroup.org/onlinepubs/9699919799/functions/bind.html
       Throws: `ErrnoException` if binding the socket fails
    */
    void bind(SocketAddr)(in auto ref SocketAddr addr) @trusted
            if (isSocketAddr!SocketAddr)
    {
        enforce(.bind(fd, addr.cargs[]) != -1, "bind failed".String);
    }

    /**
       Bind UDP socket to IP `addr` and `port`. A port number of zero will be
       bound to an ephemeral port.

       Params:
         addr = IP address to bind
         port = port number to bind
    */
    void bind(IPAddr)(IPAddr addr, ushort port = 0) if (isIPAddr!IPAddr)
    {
        bind(addr.socketAddr(port));
    }

    ///
    unittest
    {
        auto s = Socket(ProtocolFamily.IPv4, SocketType.dgram);
        s.bind(IPv4Addr(127, 0, 0, 1), 1234);
        auto localAddr = s.localAddr.get!SocketAddrIPv4;
        assert(s.isOpen);
        assert(localAddr.ip == IPv4Addr(127, 0, 0, 1));
        assert(localAddr.port == 1234);

        s = Socket(ProtocolFamily.IPv4, SocketType.dgram);
        s.bind(IPv4Addr(127, 0, 0, 1)); // ephemeral port
        localAddr = s.localAddr.get!SocketAddrIPv4;
        assert(s.isOpen);
        assert(localAddr.ip == IPv4Addr(127, 0, 0, 1));
        assert(localAddr.port != 1234);
        assert(localAddr.port != 0);

        import std.io.exception : IOException;

        bool thrown;
        try
            // cannot rebind
            s.bind(IPv4Addr(127, 0, 0, 1));
        catch (IOException)
            thrown = true;
        assert(thrown);
    }

    /**
       Connect socket to remote `addr`

       Params:
         addr = socket address to connect to
    */
    void connect(SocketAddr)(in auto ref SocketAddr addr) @trusted
            if (isSocketAddr!SocketAddr)
    {
        enforce(.connect(fd, addr.cargs[]) != -1, "connect failed".String);
    }

    /**
       Connect socket to remote IP `addr` and `port`.

       Params:
         addr = IP address to connect to
         port = port number to connect to
    */
    void connect(IPAddr)(IPAddr addr, ushort port = 0) if (isIPAddr!IPAddr)
    {
        connect(addr.socketAddr(port));
    }

    ///
    unittest
    {
        auto server = Socket(ProtocolFamily.IPv4, SocketType.dgram);
        server.bind(IPv4Addr(127, 0, 0, 1));

        auto client = Socket(ProtocolFamily.IPv4, SocketType.dgram);
        client.connect(server.localAddr);
    }

    /**
       Listen for incoming connections.

       Params:
         backlog = maximum number of pending connections
    */
    void listen(uint backlog = 128) @trusted
    {
        enforce(.listen(fd, backlog) != -1, "listen failed".String);
    }

    ///
    unittest
    {
        auto server = Socket(ProtocolFamily.IPv4, SocketType.stream);
        server.bind(IPv4Addr(127, 0, 0, 1));
        server.listen();
    }

    /**
       Accept an incoming client connection.

       Params:
         remoteAddr = client socket address
    */
    Socket accept(ref SocketAddr remoteAddr) @trusted
    {
        socklen_t addrlen = remoteAddr.sizeof;
        immutable fd = .accept(fd, cast(sockaddr*)&remoteAddr, &addrlen);
        assert(addrlen <= remoteAddr.sizeof);
        enforce(fd != -1, "accept failed".String);
        return Socket(fd);
    }

    ///
    unittest
    {
        auto server = Socket(ProtocolFamily.IPv4, SocketType.stream);
        server.bind(IPv4Addr(127, 0, 0, 1));
        server.listen();
        auto client = Socket(ProtocolFamily.IPv4, SocketType.stream);
        client.connect(server.localAddr);
        ubyte[4] ping = ['p', 'i', 'n', 'g'];
        client.send(ping[]);

        // accept client connection
        SocketAddr clientAddr;
        auto conn = server.accept(clientAddr);
        assert(clientAddr == client.localAddr);
        ubyte[4] buf;
        assert(conn.recv(buf[]) == 4);
        assert(buf[] == ping[]);
    }

    /// get local addr of socket
    SocketAddr localAddr() const @trusted
    {
        assert(isOpen);
        SocketAddr ret;
        socklen_t addrlen = ret.sizeof;
        import core.stdc.stdio;

        immutable rc = .getsockname(fd, cast(sockaddr*)&ret, &addrlen);
        enforce(rc != -1, "getsockname failed".String);
        assert(addrlen <= ret.sizeof);
        return ret;
    }

    /**
       Set socket option.

       Params:
         option = option to set
         value = value for option
    */
    void setOption(SocketOption option)(const scope SocketOptionType!option value) @trusted
    {
        immutable res = .setsockopt(fd, SOL_SOCKET, option, &value, value.sizeof);
        enforce(res != -1, "setsockopt failed".String);
    }

    ///
    unittest
    {
        auto sock = Socket(ProtocolFamily.IPv4, SocketType.dgram);
        sock.setOption!(SocketOption.reuseAddr)(true);
    }

    SocketOptionType!option getOption(SocketOption option)() @trusted
    {
        SocketOptionType!option ret = void;
        socklen_t optlen = ret.sizeof;
        immutable res = .getsockopt(fd, SOL_SOCKET, option, &ret, &optlen);
        assert(optlen == ret.sizeof);
        enforce(res != -1, "setsockopt failed".String);
        return ret;
    }

    ///
    unittest
    {
        auto sock = Socket(ProtocolFamily.IPv4, SocketType.dgram);
        sock.setOption!(SocketOption.reuseAddr)(true);
        assert(sock.getOption!(SocketOption.reuseAddr) == 1);
        assert(sock.getOption!(SocketOption.type) == SocketType.dgram);
    }

    /**
       Receive data from any address and port into buffer.

       Params:
         buf = buffer to read into
       Returns:
         number of bytes read and source address
     */
    Tuple!(size_t, "size", SocketAddr, "remoteAddr") recvFrom(scope ubyte[] buf) @trusted
    {
        typeof(return) ret = void;
        version (Posix)
        {
            socklen_t addrlen = ret[1].sizeof;
            immutable n = .recvfrom(fd, buf.ptr, buf.length, 0,
                    cast(sockaddr*)&ret[1], &addrlen);
            assert(addrlen <= ret[1].sizeof);
            enforce(n != -1, "Failed to receive from socket.".String);
            ret[0] = n;
        }
        else version (Windows)
        {
            DWORD n, flags;
            socklen_t addrlen = ret[1].sizeof;
            immutable res = .WSARecvFrom(fd, cast(WSABUF*)&buf, 1, &n,
                    &flags, cast(sockaddr*)&ret[1], &addrlen, null, null);
            enforce(res == 0, "recv failed".String);
            ret[0] = n;
        }
        return ret;
    }

    ///
    unittest
    {
        auto server = Socket(ProtocolFamily.IPv4, SocketType.dgram);
        server.bind(IPv4Addr(127, 0, 0, 1));

        auto client = Socket(ProtocolFamily.IPv4, SocketType.dgram);
        client.bind(IPv4Addr(127, 0, 0, 1));
        ubyte[4] ping = ['p', 'i', 'n', 'g'];
        client.sendTo(server.localAddr, ping[]);

        ubyte[4] buf;
        auto res = server.recvFrom(buf[]);
        assert(res.size == 4);
        assert(res.remoteAddr == client.localAddr);
        assert(buf[] == ping[]);
    }

    ///
    unittest
    {
        auto server = Socket(ProtocolFamily.IPv4, SocketType.dgram);
        server.bind(IPv4Addr(127, 0, 0, 1));

        auto client = Socket(ProtocolFamily.IPv4, SocketType.dgram);
        client.bind(IPv4Addr(127, 0, 0, 1));
        ubyte[4] buf1 = [0, 1, 2, 3];
        client.sendTo(server.localAddr, buf1[]);

        ubyte[4] buf2;
        auto res = server.recvFrom(buf2[]);
        assert(res.size == 4);
        assert(res.remoteAddr == client.localAddr);
    }

    /**
       Receive data from any address and port into multiple buffers.
       The read will be atomic on Posix and Windows platforms.

       Params:
         bufs = buffers to read into
       Returns:
         number of bytes read and source address
     */
    Tuple!(size_t, "size", SocketAddr, "remoteAddr") recvFrom(scope ubyte[][] bufs...) @trusted
    {
        typeof(return) ret = void;
        version (Posix)
        {
            auto vecs = tempIOVecs(bufs);
            msghdr msg = void;
            msg.msg_name = &ret[1];
            msg.msg_namelen = ret[1].sizeof;
            msg.msg_iov = vecs.ptr;
            msg.msg_iovlen = cast(int)vecs.length;
            msg.msg_control = null;
            msg.msg_controllen = 0;
            msg.msg_flags = 0;
            immutable flags = 0;
            immutable n = .recvmsg(fd, &msg, flags);
            assert(msg.msg_namelen <= ret[1].sizeof);
            enforce(n != -1, "read failed".String);
            ret[0] = n;
        }
        else version (Windows)
        {
            DWORD n, flags;
            socklen_t addrlen = ret[1].sizeof;
            immutable res = .WSARecvFrom(fd, cast(WSABUF*) bufs.ptr,
                    cast(uint) bufs.length, &n, &flags,
                    cast(sockaddr*)&ret[1], &addrlen, null, null);
            enforce(res == 0, "recv failed".String);
            ret[0] = n;
        }
        return ret;
    }

    ///
    unittest
    {
        auto server = Socket(ProtocolFamily.IPv4, SocketType.dgram);
        server.bind(IPv4Addr(127, 0, 0, 1));

        auto client = Socket(ProtocolFamily.IPv4, SocketType.dgram);
        client.bind(IPv4Addr(127, 0, 0, 1));
        ubyte[4] ping = ['p', 'i', 'n', 'g'];
        client.sendTo(server.localAddr, ping[]);

        ubyte[2] a, b;
        auto ret = server.recvFrom(a[], b[]);
        assert(ret.size == 4);
        assert(ret.remoteAddr == client.localAddr);
        assert(a[] == ping[0 .. 2] && b[] == ping[2 .. 4]);
    }

    /**
       Send buffer content to the specified `addr`.

       Params:
         dest = destination address
         buf = buffer to write
       Returns:
         number of bytes written
     */
    size_t sendTo(SocketAddr)(SocketAddr dest, const scope ubyte[] buf) @trusted
            if (isSocketAddr!SocketAddr)
    {
        version (Posix)
        {
            immutable flags = 0;
            immutable ret = .sendto(fd, buf.ptr, buf.length, flags, dest.cargs[]);
            enforce(ret != -1, "sendTo failed".String);
            return ret;
        }
        else version (Windows)
        {
            DWORD n, flags;
            immutable res = .WSASendTo(fd, cast(WSABUF*)&buf, 1, &n, flags,
                    dest.cargs[], null, null);
            enforce(!res, "sendTo failed".String);
            return n;
        }
    }

    /**
       Send multiple buffer contents to the specified `addr` and `port`.
       The write will be atomic on Posix and Windows platforms.

       Params:
         dest = destination address
         bufs = buffers to write
       Returns:
         total number of bytes written
     */
    size_t sendTo(SocketAddr)(SocketAddr dest, const scope ubyte[][] bufs...) @trusted
            if (isSocketAddr!SocketAddr)
    {
        version (Posix)
        {
            typeof(return) ret = void;
            auto vecs = tempIOVecs(bufs);
            msghdr msg = void;
            msg.msg_name = &dest;
            msg.msg_namelen = dest.cargs[1];
            msg.msg_iov = vecs.ptr;
            msg.msg_iovlen = vecs.length;
            msg.msg_control = null;
            msg.msg_controllen = 0;
            msg.msg_flags = 0;
            immutable flags = 0;
            immutable n = .sendmsg(fd, &msg, flags);
            enforce(n != -1, "sendTo failed".String);
            return n;
        }
        else version (Windows)
        {
            DWORD n, flags;
            immutable res = .WSASendTo(fd, cast(WSABUF*) bufs.ptr,
                    cast(uint) bufs.length, &n, flags, dest.cargs[], null, null);
            enforce(!res, "sendTo failed".String);
            return n;
        }
    }

    ///
    unittest
    {
        auto server = Socket(ProtocolFamily.IPv4, SocketType.dgram);
        server.bind(IPv4Addr(127, 0, 0, 1));

        auto client = Socket(ProtocolFamily.IPv4, SocketType.dgram);
        client.bind(IPv4Addr(127, 0, 0, 1));
        ubyte[2] pi = ['p', 'i'], ng = ['n', 'g'];
        client.sendTo(server.localAddr, pi[], ng[]);

        ubyte[4] buf;
        assert(server.recv(buf[]) == 4);
        assert(buf[0 .. 2] == pi[] && buf[2 .. 4] == ng[]);
    }

    /**
       Receive from socket into buffer.

       Params:
         buf = buffer to read into
       Returns:
         number of bytes read
    */
    size_t recv(scope ubyte[] buf) @trusted
    {
        version (Posix)
        {
            immutable ret = .recv(fd, &buf[0], buf.length, 0);
            enforce(ret != -1, "recv failed".String);
            return ret;
        }
        else version (Windows)
        {
            DWORD n, flags;
            immutable ret = .WSARecv(fd, cast(WSABUF*)&buf, 1, &n, &flags, null, null);
            enforce(ret == 0, "WSARecv failed".String);
            return n;
        }
    }

    /**
       Receive from socket into multiple buffers.
       The read will be atomic on Posix and Windows platforms.

       Params:
         bufs = buffers to read into
       Returns:
         total number of bytes read
    */
    size_t recv(scope ubyte[][] bufs...) @trusted
    {
        version (Posix)
        {
            auto vecs = tempIOVecs(bufs);
            immutable ret = .readv(fd, vecs.ptr, cast(int) bufs.length);
            enforce(ret != -1, "recv failed".String);
            return ret;
        }
        else version (Windows)
        {
            DWORD n, flags;
            immutable ret = .WSARecv(fd, cast(WSABUF*) bufs.ptr,
                    cast(uint) bufs.length, &n, &flags, null, null);
            enforce(ret == 0, "WSARecv failed".String);
            return n;
        }
    }

    /**
       Alias to comply with input `IO` API.

       See_also: $(REF std,io,isInput)
     */
    alias read = recv;

    /**
       Send buffer to connected host.

       Params:
         buf = buffer to write
       Returns:
         number of bytes written
    */
    size_t send(const scope ubyte[] buf) @trusted
    {
        version (Posix)
        {
            immutable ret = .send(fd, &buf[0], buf.length, 0);
            enforce(ret != -1, "send failed".String);
            return ret;
        }
        else version (Windows)
        {
            DWORD n, flags;
            immutable ret = .WSASend(fd, cast(WSABUF*)&buf, 1, &n, flags, null, null);
            enforce(ret == 0, "send failed".String);
            return n;
        }
    }

    /**
       Send multiple buffers to connected host.
       The writes will be atomic on Posix platforms.

       Params:
         bufs = buffers to write
       Returns:
         total number of bytes written
    */
    size_t send(const scope ubyte[][] bufs...) @trusted
    {
        version (Posix)
        {
            auto vecs = tempIOVecs(bufs);
            immutable ret = .writev(fd, vecs.ptr, cast(int) vecs.length);
            enforce(ret != -1, "send failed".String);
            return ret;
        }
        else version (Windows)
        {
            DWORD n, flags;
            immutable ret = .WSASend(fd, cast(WSABUF*) bufs.ptr,
                    cast(uint) bufs.length, &n, flags, null, null);
            enforce(ret == 0, "send failed".String);
            return n;
        }
    }

    /**
       Alias to comply with output `IO` API.

       See_also: $(REF std,io,isOutput)
     */
    alias write = send;

    /// move operator for socket
    Socket move()
    {
        immutable fd = this.fd;
        this.fd = Socket.init.fd;
        return Socket(fd);
    }

    /// not copyable
    @disable this(this);

package(std.io.net):
    version (Posix) enum INVALID_SOCKET = -1;
    version (Posix) int fd = INVALID_SOCKET;
    version (Windows) SOCKET fd = INVALID_SOCKET;

private:
    import std.typecons : Tuple;
}

version (Windows) package(std.io.net) void initWSA() @nogc
{
    import core.atomic;
    import core.stdc.stdlib : atexit;

    static shared bool initialized;
    if (!atomicLoad!(MemoryOrder.raw)(initialized))
    {
        WSADATA wd;
        enforce(!WSAStartup(0x2020, &wd), "WSAStartup failed".String);
        static extern (C) void cleanup()
        {
            WSACleanup();
        }

        if (cas(&initialized, false, true))
            atexit(&cleanup);
    }
}
