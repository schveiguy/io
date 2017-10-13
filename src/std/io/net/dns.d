/**
   Domain Name Resolver

   License: $(HTTP boost.org/LICENSE_1_0.txt, Boost License 1.0).
   Authors: Martin Nowak
   Source: $(PHOBOSSRC std/io/net/_dns.d)
*/
module std.io.net.dns;

import std.io.exception : enforce, ErrnoException;
import std.io.internal.string;
import std.io.net.addr;
import std.io.net.socket;
import std.range, std.traits;

/**
   Resolved Address Info
*/
struct AddrInfo
{
pure nothrow @safe @nogc:
    /// resolved address family
    AddrFamily family() const scope
    {
        return cast(AddrFamily) ai.ai_family;
    }

    /// resolved socket type
    SocketType socketType() const scope
    {
        return cast(SocketType) ai.ai_socktype;
    }

    /// resolved protocol
    Protocol protocol() const scope
    {
        return cast(Protocol) ai.ai_protocol;
    }

    /// get resolved socket address
    SocketAddr addr() @trusted scope
    {
        import core.stdc.string : memcpy;

        SocketAddr addr;
        memcpy( & addr, ai.ai_addr, ai.ai_addrlen);
        return addr;
    }

private:
    version (Posix)
        import core.sys.posix.netdb : addrinfo;
    else
        import core.sys.windows.winsock2 : addrinfo;

    const(addrinfo)* ai;
}

/**
   Resolve `hostname` to a forward range of `AddrInfo` using `service`
   or `port`, `family`, `socktype`, and `protocol` as hints.

See_also: https://www.iana.org/assignments/service-names-port-numbers
 */
auto resolve(S1, S2)(S1 hostname, S2 service, AddrFamily family = AddrFamily.unspecified,
        SocketType socktype = SocketType.unspecified, Protocol protocol = Protocol.default_) @nogc @trusted
        if (isSomeString!S1 && isSomeString!S2)
{
    return getAddrInfo(hostname, service, family, socktype, protocol, 0);
}

/// ditto
auto resolve(S1)(S1 hostname, ushort port, AddrFamily family = AddrFamily.unspecified,
        SocketType socktype = SocketType.unspecified, Protocol protocol = Protocol.default_) @nogc @trusted
        if (isSomeString!S1)
{
    import core.internal.string : unsignedToTempString;

    version (Posix)
    {
        import core.sys.posix.netdb : AI_NUMERICSERV;

        enum flags = AI_NUMERICSERV;
    }
    else
        enum flags = 0;

    return getAddrInfo(hostname, unsignedToTempString(port, 10)[], family,
            socktype, protocol, flags);
}

private auto getAddrInfo(S1, S2)(S1 hostname, S2 service, AddrFamily family = AddrFamily.unspecified,
        SocketType socktype = SocketType.unspecified,
        Protocol protocol = Protocol.default_, int flags = 0) @nogc @trusted
        if (isSomeString!S1 && isSomeString!S2)
{
    version (Posix)
        import core.sys.posix.netdb;
    else version (Windows)
        import core.sys.windows.winsock2;
    else
        static assert(0, "unimplemented");

    version (Windows)
    {
        import std.io.net.socket : initWSA;

        initWSA();
    }

    import std.internal.cstring : tempCString;

    addrinfo hints;
    with (hints)
    {
        version (Posix)
            ai_flags = flags | AI_V4MAPPED | AI_ADDRCONFIG;
        else
            ai_flags = flags | AI_ADDRCONFIG;
        ai_family = family;
        ai_socktype = socktype;
        ai_protocol = protocol;
        ai_addrlen = 0;
        ai_canonname = null;
        ai_addr = null;
        ai_next = null;
    }
    addrinfo* res;
    immutable ret = getaddrinfo(tempCString(hostname), tempCString(service), &hints, &res);
    enforce!DNSException(ret == 0, {
        auto s = String("failed to resolve '");
        s ~= hostname;
        s ~= ':';
        s ~= service;
        s ~= '\'';
        return s.move;
    }, ret);
    return GAIResult(res);
}

private struct GAIResult
{
nothrow @safe @nogc:
    AddrInfo front() pure const return scope @trusted
    {
        return AddrInfo(ai);
    }

    bool empty() pure const scope
    {
        return ai is null;
    }

    void popFront() pure scope
    {
        import std.stdio;

        assert(ai !is null);
        ai = ai.ai_next;
    }

    ~this() @trusted scope
    {
        freeaddrinfo(cast(addrinfo * ) ai);
        ai = null;
    }

    @disable this(this);

    const(addrinfo)* ai;
private:
    version (Posix)
        import core.sys.posix.netdb : addrinfo, freeaddrinfo;
    else version (Windows)
        import core.sys.windows.winsock2 : addrinfo, freeaddrinfo;
}

///
@safe @nogc unittest
{
    auto rng = resolve("localhost", "http", AddrFamily.IPv4);
    assert(!rng.empty);
    auto addr4 = rng.front.addr.get!SocketAddrIPv4;
    assert(addr4.ip == IPv4Addr(127, 0, 0, 1));
    assert(addr4.port == 80);

    rng = resolve("localhost", "http", AddrFamily.IPv6);
    assert(!rng.empty);
    auto addr6 = rng.front.addr.get!SocketAddrIPv6;
    assert(addr6.ip == IPv6Addr(0, 0, 0, 0, 0, 0, 0, 1));
    assert(addr6.port == 80);
}

/// exception thrown on name resolution errors
class DNSException : ErrnoException
{
    immutable int gaiError; /// getaddrinfo error code

    this(String msg, uint gaiError) @safe @nogc
    {
        super(msg.move);
        this.gaiError = gaiError;
    }

protected:
    override void ioError(scope void delegate(const scope char[]) nothrow @safe sink) const nothrow @trusted
    {
        import core.stdc.string : strlen;

        version (Windows)
        {
            import core.sys.windows.winbase;

            char[256] buf = void;
            immutable n = FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
                    null, gaiError, 0, buf.ptr, buf.length, null);
            sink(": ");
            if (n)
            {
                sink(buf[0 .. n]);
                sink(" ");
            }
        }
        else version (Posix)
        {
            import core.sys.posix.netdb : gai_strerror, EAI_SYSTEM;
            import core.stdc.string : strlen;

            if (gaiError == EAI_SYSTEM)
                return super.ioError(sink);
            auto p = gai_strerror(gaiError);
            if (p is null)
                return;
            sink(": ");
            if (p !is null)
            {
                sink(p[0 .. p.strlen]);
                sink(" ");
            }
        }

        import core.internal.string : signedToTempString;

        sink("(error=");
        sink(signedToTempString(gaiError, 10));
        sink(")");
    }

private:
    String msg;
}
