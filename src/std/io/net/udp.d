/**
   UDP datagram sockets

   License: $(HTTP boost.org/LICENSE_1_0.txt, Boost License 1.0).
   Authors: Martin Nowak
   Source: $(PHOBOSSRC std/io/net/_udp.d)
*/
module std.io.net.udp;

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
   A UDP/Datagram socket
 */
struct UDP
{
@safe @nogc:
    /**
       Create a UDP socket and bind it to the resolved `hostname` and `port`.
       Uses the first resolved address the socket can successfully bind.
       A port number of zero will be bound to an ephemeral port.

       Params:
         hostname = hostname to resolve and bind
         port = port number to bind
    */
    static UDP server(S)(S hostname, ushort port = 0) if (isStringLike!S)
    {
        return bindAddrInfos(resolve(hostname, port, AddrFamily.unspecified, SocketType.dgram));
    }

    ///
    unittest
    {
        auto server = UDP.server("localhost", 1234);
        auto client = UDP(server.localAddr.family);
        ubyte[4] ping = ['p', 'i', 'n', 'g'];
        client.sendTo(server.localAddr, ping[]);
        ubyte[4] buf;
        assert(server.recv(buf[]) == 4);
        assert(buf[] == ping[]);
    }

    /**
       Create a UDP socket and bind it to the resolved `hostname` and `service`.
       Uses the first resolved address the socket can successfully bind.

       Params:
         hostname = hostname to resolve and bind
         service = service name to resolve and bind
    */
    static UDP server(S1, S2)(S1 hostname, S2 service)
            if (isStringLike!S1 && isStringLike!S2)
    {
        return bindAddrInfos(resolve(hostname, service, AddrFamily.unspecified, SocketType.dgram));
    }

    ///
    unittest
    {
        auto server = UDP.server("localhost", 1234);
        auto client = UDP(server.localAddr.family);
        ubyte[4] ping = ['p', 'i', 'n', 'g'];
        client.sendTo(server.localAddr, ping[]);
        ubyte[4] buf;
        assert(server.recv(buf[]) == 4);
        assert(buf[] == ping[]);
    }

    /**
       Create a UDP socket and bind it to socket `addr`.

       Params:
         addr = socket address to bind
    */
    static UDP server(SocketAddr)(in auto ref SocketAddr addr)
            if (isSocketAddr!SocketAddr)
    {
        auto res = UDP(addr.family);
        res.bind(addr);
        return res;
    }

    ///
    unittest
    {
        auto addr4 = SocketAddrIPv4(IPv4Addr(127, 0, 0, 1), 1234);
        auto server = UDP.server(addr4);
        assert(server.localAddr == addr4);

        auto addr6 = SocketAddrIPv6(IPv6Addr(0, 0, 0, 0, 0, 0, 0, 1), 1234);
        server = UDP.server(addr6);
        assert(server.localAddr == addr6);
    }

    /**
       Create a UDP socket and bind it to IP `addr` and `port`. A port
       number of zero will be bound to an ephemeral port.

       Params:
         addr = IP address to bind
         port = port number to bind
    */
    static UDP server(IPAddr)(IPAddr addr, ushort port = 0) if (isIPAddr!IPAddr)
    {
        return server(addr.socketAddr(port));
    }

    ///
    unittest
    {
        auto server = UDP.server(IPv4Addr(127, 0, 0, 1));
        assert(server.localAddr.get!SocketAddrIPv4.ip == IPv4Addr(127, 0, 0, 1));
        assert(server.localAddr.get!SocketAddrIPv4.port != 0);
    }

    private static UDP bindAddrInfos(R)(R addrInfos) @trusted
    {
        for (auto ai = addrInfos.front; !addrInfos.empty; addrInfos.popFront)
        {
            auto ret = UDP(ai.family);
            ret.setOption!(SocketOption.reuseAddr)(true);
            immutable res = .bind(ret.socket.fd, ai.addr.cargs[]);
            if (res != -1)
                return ret.move;
        }
        enforce(0, "bind failed".String);
        assert(0);
    }

    /**
       Connect to resolved `hostname` and `port`.
       Uses the first resolved address the socket can successfully connect to.

       UDP is a connection-less protocol. Connecting to a client to a remote
       address allows to use `send` without specifying a destination address. It
       will also apply a filter to only receive traffic from the connected
       address.

       Params:
         hostname = remote hostname to connect to
         port = remote port to connect to
     */
    static UDP client(S)(S hostname, ushort port) if (isStringLike!S)
    {
        return connectAddrInfos(resolve(hostname, port, AddrFamily.unspecified, SocketType.dgram));
    }

    ///
    unittest
    {
        auto server = UDP.server("localhost", 1234);
        // connect to remote hostname and port
        auto client = UDP.client("localhost", 1234);

        // send to connected address
        ubyte[4] ping = ['p', 'i', 'n', 'g'];
        client.send(ping[]);
        ubyte[4] buf;
        assert(server.recv(buf[]) == 4);
        assert(buf[] == ping[]);
    }

    /**
       Connect to resolved `hostname` and `service`.
       Uses the first resolved address the socket can successfully connected to.

       Params:
         hostname = remote hostname to connect to
         service = service to connect to

       See_also: https://www.iana.org/assignments/service-names-port-numbers
     */
    static UDP client(S1, S2)(S1 hostname, S2 service)
            if (isStringLike!S1 && isStringLike!S2)
    {
        return connectAddrInfos(resolve(hostname, service,
                AddrFamily.unspecified, SocketType.dgram));
    }

    ///
    unittest
    {
        auto server = UDP.server("localhost", "msnp");
        // "connect" to remote hostname and service
        auto client = UDP.client("localhost", "msnp");

        // send to connected address
        ubyte[4] ping = ['p', 'i', 'n', 'g'];
        client.send(ping[]);
        ubyte[4] buf;
        assert(server.recv(buf[]) == 4);
        assert(buf[] == ping[]);
    }

    /**
       Connect to remote socket address.

       Params:
         addr = remote socket address to connect to
     */
    static UDP client(SocketAddr)(in auto ref SocketAddr addr) @trusted 
            if (isSocketAddr!SocketAddr)
    {
        auto res = UDP(addr.family);
        res.connect(addr);
        return res;
    }

    ///
    unittest
    {
        auto server = UDP.server("localhost");
        // "connect" to remote address
        auto client = UDP.client(server.localAddr);

        // send to connected address
        ubyte[4] ping = ['p', 'i', 'n', 'g'];
        client.send(ping[]);
        ubyte[4] buf;
        assert(server.recv(buf[]) == 4);
        assert(buf[] == ping[]);

        // can still use sendTo with other addr
        auto server2 = UDP.server("localhost");
        client.sendTo(server2.localAddr, ping[]);
        assert(server2.recv(buf[]) == 4);
        assert(buf[] == ping[]);

        // while keep sending to connected address
        client.send(ping[]);
        assert(server.recv(buf[]) == 4);
        assert(buf[] == ping[]);

        // client can only receive data from connected server
        server.sendTo(client.localAddr, ping[]);
        assert(client.recv(buf[]) == 4);
        assert(buf[] == ping[]);
    }

    /**
       Connect to remote IP `addr` and `port`.

       Params:
         addr = remote IP address to connect to
         port = remote port to connect to
     */
    static UDP client(IPAddr)(IPAddr addr, ushort port = 0) if (isIPAddr!IPAddr)
    {
        return client(addr.socketAddr(port));
    }

    ///
    unittest
    {
        auto server = UDP.server(IPv4Addr(127, 0, 0, 1), 1234);
        // "connect" to remote IP address and port
        auto client = UDP.client(IPv4Addr(127, 0, 0, 1), 1234);

        // send to connected address
        ubyte[4] ping = ['p', 'i', 'n', 'g'];
        client.send(ping[]);
        ubyte[4] buf;
        assert(server.recv(buf[]) == 4);
        assert(buf[] == ping[]);
    }

    private static UDP connectAddrInfos(R)(R addrInfos) @trusted
    {
        for (auto ai = addrInfos.front; !addrInfos.empty; addrInfos.popFront)
        {
            auto ret = UDP(ai.family);
            immutable res = .connect(ret.socket.fd, ai.addr.cargs[]);
            if (res != -1)
                return ret.move;
        }
        enforce(0, "connect failed".String);
        assert(0);
    }

    ///
    unittest
    {
        auto server = UDP.server(IPv4Addr(127, 0, 0, 1), 1234);
        // "connect" to remote IP address and port
        auto client = UDP.client(IPv4Addr(127, 0, 0, 1), 1234);

        // send to connected address
        ubyte[4] ping = ['p', 'i', 'n', 'g'];
        client.send(ping[]);
        ubyte[4] buf;
        assert(server.recv(buf[]) == 4);
        assert(buf[] == ping[]);
    }

    /**
       Construct an unbound UDP socket for the given protocol `family`. It will
       be automatically bound to an address on the first call to `sendto`.

       Params:
         family = protocol family for socket
    */
    this(ProtocolFamily family)
    {
        socket = Socket(family, SocketType.dgram);
    }

    ///
    unittest
    {
        auto server = UDP.server(IPv4Addr(127, 0, 0, 1));
        auto client = UDP(ProtocolFamily.IPv4);
        // unbound
        SocketAddrIPv4 addr;
        // cannot get unbound localAddr on Windows
        version (Posix)
        {
            addr = client.localAddr.get!SocketAddrIPv4;
            assert(addr.ip == IPv4Addr.any); // 0.0.0.0
            assert(addr.port == 0);
        }
        ubyte[4] ping = ['p', 'i', 'n', 'g'];
        client.sendTo(server.localAddr, ping[]);
        // now bound
        addr = client.localAddr.get!SocketAddrIPv4;
        assert(addr.ip == IPv4Addr.any);
        assert(addr.port != 0);

        // client can receive data from any peer
        auto peer = UDP(ProtocolFamily.IPv4);
        // cannot sendTo 0.0.0.0 on Windows
        version (Windows)
            addr.ip = IPv4Addr(127, 0, 0, 1);
        peer.sendTo(addr, ping[]);
        ubyte[4] buf;
        assert(client.recv(buf[]) == 4);
        assert(buf[] == ping[]);
    }

    /// move operator for socket
    UDP move()
    {
        return UDP(socket.move);
    }

    /// underlying `Socket`
    Socket socket;

    /// forward to `socket`
    alias socket this;

private:
    // take ownership of socket
    this(Socket socket)
    {
        this.socket = socket.move;
    }
}

///
unittest
{
    auto server = UDP.server(IPv4Addr(127, 0, 0, 1));
    auto client = UDP(ProtocolFamily.IPv4);

    ubyte[4] ping = ['p', 'i', 'n', 'g'];
    client.sendTo(server.localAddr, ping[]);

    ubyte[4] buf;
    auto res = server.recvFrom(buf[]);
    assert(res.size == 4);
    assert(buf[] == ping[]);

    ubyte[4] pong = ['p', 'o', 'n', 'g'];
    server.sendTo(res.remoteAddr, pong[]);

    assert(client.recv(buf[]) == 4);
    assert(buf[] == pong[]);
}
