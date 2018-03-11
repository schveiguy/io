/**
   Low-level sockets

   License: $(HTTP boost.org/LICENSE_1_0.txt, Boost License 1.0).
   Authors: Martin Nowak
   Source: $(PHOBOSSRC std/io/net/_socket.d)
*/
module std.io.net.socket;

import std.io.driver;
import std.io.exception : enforce, IOException;
import std.io.internal.string;
import std.io.net.addr;

version (Posix)
{
    import core.sys.posix.netinet.in_;
    import core.sys.posix.sys.socket;
}
else version (Windows)
{
    import core.sys.windows.winsock2;
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
        s = driver.createSocket(family, type, protocol);
    }

    /// take ownership of an existing socket `handle`
    version (Posix)
        this(int handle)
    {
        s = driver.socketFromHandle(handle);
    }
    else version (Windows)
        this(SOCKET handle)
    {
        s = driver.socketFromHandle(handle);
    }

    ///
    ~this()
    {
        close();
    }

    /// close the socket
    void close() @trusted
    {
        if (s == Driver.INVALID_SOCKET)
            return;
        driver.closeSocket(s);
        s = Driver.INVALID_SOCKET;
    }

    /// return whether the socket is open
    bool isOpen() const pure nothrow
    {
        return s != Driver.INVALID_SOCKET;
    }

    ///
    unittest
    {
        Socket s;
        assert(!s.isOpen);
        s = Socket(ProtocolFamily.IPv4, SocketType.dgram);
        assert(s.isOpen);
        s.close;
        assert(!s.isOpen);
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
        driver.bind(s, addr.cargs[]);
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
        driver.connect(s, addr.cargs[]);
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
        driver.listen(s, backlog);
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
        return Socket(driver.accept(s, cast(sockaddr*)&remoteAddr, addrlen));
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
        SocketAddr ret = void;
        socklen_t addrlen = ret.sizeof;
        driver.localAddr(s, cast(sockaddr*)&ret, addrlen);
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
        driver.setSocketOption(s, option, &value, value.sizeof);
    }

    ///
    unittest
    {
        auto sock = Socket(ProtocolFamily.IPv4, SocketType.dgram);
        sock.setOption!(SocketOption.reuseAddr)(true);
    }

    /**
       Get socket option.

       Params:
         option = option to get
    */
    SocketOptionType!option getOption(SocketOption option)() const @trusted
    {
        SocketOptionType!option ret = void;
        socklen_t optlen = ret.sizeof;
        driver.getSocketOption(s, option, &ret, optlen);
        assert(optlen == ret.sizeof);
        return ret;
    }

    ///
    unittest
    {
        auto sock = Socket(ProtocolFamily.IPv4, SocketType.dgram);
        sock.setOption!(SocketOption.reuseAddr)(true);
        assert(!!sock.getOption!(SocketOption.reuseAddr));
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
        socklen_t addrlen = ret[1].sizeof;
        ret[0] = driver.recvFrom(s, buf, cast(sockaddr*)&ret[1], addrlen);
        assert(addrlen <= ret[1].sizeof);
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
        socklen_t addrlen = ret[1].sizeof;
        ret[0] = driver.recvFrom(s, bufs, cast(sockaddr*)&ret[1], addrlen);
        assert(addrlen <= ret[1].sizeof);
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
        return driver.sendTo(s, buf, dest.cargs[]);
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
        return driver.sendTo(s, bufs, dest.cargs[]);
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
        return driver.recv(s, buf);
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
        return driver.recv(s, bufs);
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
        return driver.send(s, buf);
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
        return driver.send(s, bufs);
    }

    /**
       Alias to comply with output `IO` API.

       See_also: $(REF std,io,isOutput)
     */
    alias write = send;

    /// move operator for socket
    Socket move() return scope nothrow /*pure Issue 18590*/
    {
        auto s = this.s;
        this.s = Driver.INVALID_SOCKET;
        return Socket(s);
    }

    /// not copyable
    @disable this(this);

package(std.io.net):

    /// get socket bound to resolved `hostname` and `service`
    static Socket resolveBind( /*in*/ const scope char[] hostname, /*in*/ const scope char[] service,
            SocketType socketType) @trusted
    {
        Socket sock;
        immutable res = driver.resolve(hostname, service,
                AddrFamily.unspecified, socketType, Protocol.default_, (ref scope ai) {
                    try
                    {
                        sock = Socket(ai.family, ai.socketType, ai.protocol);
                        sock.setOption!(SocketOption.reuseAddr)(true);
                        sock.bind(ai.addr);
                    }
                    catch (IOException)
                        return 0;
                    return 1;
                });
        enforce(res == 1, "bind failed".String);
        return sock.move;
    }

    /// get socket connected to resolved `hostname` and `service`
    static Socket resolveConnect( /*in*/ const scope char[] hostname, /*in*/ const scope char[] service,
            SocketType socketType) @trusted
    {
        Socket sock;
        immutable res = driver.resolve(hostname, service,
                AddrFamily.unspecified, socketType, Protocol.default_, (ref scope ai) {
                    try
                    {
                        sock = Socket(ai.family, ai.socketType, ai.protocol);
                        sock.setOption!(SocketOption.reuseAddr)(true);
                        sock.connect(ai.addr);
                    }
                    catch (IOException)
                        return 0;
                    return 1;
                });
        enforce(res == 1, "connect failed".String);
        return sock.move;
    }

private:
    import std.typecons : Tuple;

    this(return scope Driver.SOCKET s) @trusted pure nothrow
    {
        this.s = s;
    }

    Driver.SOCKET s = Driver.INVALID_SOCKET;
}
