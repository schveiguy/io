/**
   TCP stream sockets

   License: $(HTTP boost.org/LICENSE_1_0.txt, Boost License 1.0).
   Authors: Martin Nowak
   Source: $(PHOBOSSRC std/io/net/_tcp.d)
*/
module std.io.net.tcp;

import std.io.exception : enforce;
import std.io.internal.string;
import std.io.net.addr;
import std.io.net.socket;
import std.io.net.dns : resolve;

version (Posix)
{
    import core.sys.posix.sys.socket;
}
else version (Windows)
{
    import core.sys.windows.winsock2;
}
else
    static assert(0, "unimplemented");

/**
   A TCP stream socket
 */
struct TCP
{
@safe @nogc:
    /**
       Create a TCP socket, bind it to the resolved `hostname` and
       `port`, and listen for incoming connections.
       Uses the first resolved address the socket can successfully bind.
       A port number of zero will be bound to an ephemeral port.

       Params:
         hostname = hostname to resolve and bind
         port = port number to bind
         backlog = maximum number of pending connections
       Returns:
         TCPServer to accept incoming connections
    */
    static TCPServer server(S)(S hostname, ushort port = 0, uint backlog = 128) @trusted
            if (isStringLike!S)
    {
        auto sock = listenAddrInfos(resolve(hostname, port,
                AddrFamily.unspecified, SocketType.stream), backlog);
        sock.listen(backlog);
        return TCPServer(sock.move);
    }

    /**
       Create a TCP socket, bind it to the resolved `hostname` and
       `service`, and listen for incoming connections.
       Uses the first resolved address the socket can successfully bind.

       Params:
         hostname = hostname to resolve and bind
         service = service bind
         backlog = maximum number of pending connections
       Returns:
         TCPServer to accept incoming connections
    */
    static TCPServer server(S1, S2)(S1 hostname, S2 service, uint backlog = 128) @trusted
            if (isStringLike!S1 && isStringLike!S2)
    {
        auto sock = listenAddrInfos(resolve(hostname, service,
                AddrFamily.unspecified, SocketType.stream), backlog);
        sock.listen(backlog);
        return TCPServer(sock.move);
    }

    /**
       Create a TCP socket, bind it to socket `addr`, and listen for
       incoming connections.

       Params:
         addr = socket address to bind
         backlog = maximum number of pending connections
    */
    static TCPServer server(SocketAddr)(in auto ref SocketAddr addr, uint backlog = 128)
            if (isSocketAddr!SocketAddr)
    {
        auto sock = Socket(addr.family, SocketType.stream, Protocol.default_);
        sock.setOption!(SocketOption.reuseAddr)(true);
        sock.bind(addr);
        sock.listen(backlog);
        return TCPServer(sock.move);
    }

    /**
       Create a TCP socket, bind it to IP `addr` and `port`, and
       listen for incoming connections.  A port number of zero will be
       bound to an ephemeral port.

       Params:
         addr = IP address to bind
         port = port to bind
         backlog = maximum number of pending connections
    */
    static TCPServer server(IPAddr)(IPAddr addr, ushort port = 0, uint backlog = 128)
            if (isIPAddr!IPAddr)
    {
        return server(addr.socketAddr(port), backlog);
    }

    private static Socket listenAddrInfos(R)(R addrInfos, uint backlog) @trusted
    {
        bool bind, listen;
        for (auto ai = addrInfos.front; !addrInfos.empty; addrInfos.popFront)
        {
            auto ret = Socket(ai.family, SocketType.stream, Protocol.default_);
            ret.setOption!(SocketOption.reuseAddr)(true);
            auto res = .bind(ret.fd, ai.addr.cargs[]);
            if (res != -1)
                return ret;
        }
        enforce(0, "bind failed".String);
        assert(0);
    }

    /**
       Connect to resolved `hostname` and `port`.
       Uses the first resolved address the socket can successfully connect to.

       Params:
         hostname = remote hostname to connect to
         port = remote port to connect to
     */
    static TCP client(S)(S hostname, ushort port) if (isStringLike!S)
    {
        return connectAddrInfos(resolve(hostname, port, AddrFamily.unspecified, SocketType.stream));
    }

    ///
    unittest
    {
        auto server = TCP.server("localhost", 1234);
        // connect to remote hostname and port
        auto client = TCP.client("localhost", 1234);

        // send to connected address
        ubyte[4] ping = ['p', 'i', 'n', 'g'];
        client.send(ping[]);

        auto conn = server.accept;
        assert(conn.remoteAddr == client.localAddr);
        ubyte[4] buf;
        assert(conn.tcp.recv(buf[]) == 4);
        assert(buf[] == ping[]);
    }

    /**
       Connect to resolved `hostname` and `service`.
       Uses the first resolved address the socket can successfully connect to.

       Params:
         hostname = remote hostname to connect to
         service = service to connect to

       See_also: https://www.iana.org/assignments/service-names-port-numbers
     */
    static TCP client(S1, S2)(S1 hostname, S2 service)
            if (isStringLike!S1 && isStringLike!S2)
    {
        return connectAddrInfos(resolve(hostname, service,
                AddrFamily.unspecified, SocketType.stream));
    }

    ///
    unittest
    {
        auto server = TCP.server("localhost", "msnp");
        // "connect" to remote hostname and service
        auto client = TCP.client("localhost", "msnp");

        // send to connected address
        ubyte[4] ping = ['p', 'i', 'n', 'g'];
        client.send(ping[]);

        auto conn = server.accept;
        assert(conn.remoteAddr == client.localAddr);
        ubyte[4] buf;
        assert(conn.tcp.recv(buf[]) == 4);
        assert(buf[] == ping[]);
    }

    /**
       Connect to remote socket address.

       Params:
         addr = remote socket address to connect to
     */
    static TCP client(SocketAddr)(in auto ref SocketAddr addr) @trusted
            if (isSocketAddr!SocketAddr)
    {
        auto sock = Socket(addr.family, SocketType.stream, Protocol.default_);
        sock.connect(addr);
        return TCP(sock.move);
    }

    ///
    unittest
    {
        auto server = TCP.server("localhost");
        // "connect" to remote address
        auto client = TCP.client(server.localAddr);

        // send to connected address
        ubyte[4] ping = ['p', 'i', 'n', 'g'];
        client.send(ping[]);

        auto conn = server.accept;
        ubyte[4] buf;
        assert(conn.recv(buf[]) == 4);
        assert(buf[] == ping[]);

        ubyte[4] pong = ['p', 'o', 'n', 'g'];
        conn.send(pong[]);

        assert(client.recv(buf[]) == 4);
        assert(buf[] == pong[]);
    }

    /**
       Connect to remote IP `addr` and `port`.

       Params:
         addr = remote IP address to connect to
         port = remote port to connect to
     */
    static TCP client(IPAddr)(IPAddr addr, ushort port = 0) if (isIPAddr!IPAddr)
    {
        return client(addr.socketAddr(port));
    }

    ///
    unittest
    {
        auto server = TCP.server(IPv4Addr(127, 0, 0, 1), 1234);
        // "connect" to remote IP address and port
        auto client = TCP.client(IPv4Addr(127, 0, 0, 1), 1234);

        // send to connected address
        ubyte[4] ping = ['p', 'i', 'n', 'g'];
        client.send(ping[]);

        auto conn = server.accept;
        ubyte[4] buf;
        assert(conn.recv(buf[]) == 4);
        assert(buf[] == ping[]);
    }

    private static TCP connectAddrInfos(R)(R addrInfos) @trusted
    {
        for (auto ai = addrInfos.front; !addrInfos.empty; addrInfos.popFront)
        {
            auto sock = Socket(ai.family, SocketType.stream, Protocol.default_);
            immutable res = .connect(sock.fd, ai.addr.cargs[]);
            if (res != -1)
                return TCP(sock.move);
        }
        enforce(0, "connect failed".String);
        assert(0);
    }

    /// underlying `Socket`
    Socket socket;

    /// forward to `socket`
    alias socket this;
}

///
unittest
{
    auto server = TCP.server(IPv4Addr(127, 0, 0, 1));
    auto client = TCP.client(server.localAddr);

    ubyte[4] ping = ['p', 'i', 'n', 'g'];
    client.write(ping[]);

    auto conn = server.accept;
    assert(conn.remoteAddr == client.localAddr);
    ubyte[4] buf;
    assert(conn.read(buf[]) == 4);
    assert(buf[] == ping[]);

    ubyte[4] pong = ['p', 'o', 'n', 'g'];
    conn.write(pong[]);

    assert(client.read(buf[]) == 4);
    assert(buf[] == pong[]);
}

/**
 */
struct TCPServer
{
@safe @nogc:
    /**
       Accepted client connection.
     */
    static struct Client
    {
        TCP tcp; /// socket connect to client
        SocketAddr remoteAddr; /// remote address of client
        alias tcp this; /// forward to socket
    }

    /**
       Accept a TCP socket from a connected client.
     */
    Client accept() @trusted
    {
        Client res;
        res.tcp = TCP(socket.accept(res.remoteAddr));
        return res;
    }

    ///
    unittest
    {
        auto server = TCP.server("localhost");
        auto client = TCP.client(server.localAddr);

        ubyte[4] ping = ['p', 'i', 'n', 'g'];
        assert(client.write(ping[]) == 4);

        auto conn = server.accept;
        assert(conn.localAddr == server.localAddr);
        assert(conn.remoteAddr == client.localAddr);
        ubyte[4] buf;
        assert(conn.read(buf[]) == 4);
        assert(buf[] == ping[]);

        ubyte[4] pong = ['p', 'o', 'n', 'g'];
        conn.write(pong[]);

        assert(client.read(buf[]) == 4);
        assert(buf[] == pong[]);
    }

    /// underlying `Socket`
    Socket socket;

    /// forward to `socket`
    alias socket this;
}
