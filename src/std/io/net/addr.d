/**
   Network addesses

   License: $(HTTP boost.org/LICENSE_1_0.txt, Boost License 1.0).
   Authors: Martin Nowak
   Source: $(PHOBOSSRC std/io/net/_addr.d)
*/
module std.io.net.addr;

version (Posix)
{
    import core.sys.posix.netinet.in_;
    import core.sys.posix.sys.socket;
    import core.sys.posix.sys.un;
}
else version (Windows)
{
    import core.sys.windows.winsock2;

    static if (__VERSION__ < 2078) // https://github.com/dlang/druntime/pull/1958
        import core.sys.windows.winsock2 : sockaddr_storage = SOCKADDR_STORAGE;
}
else
    static assert(0, "unimplemented");

import std.typecons : tuple, Tuple;
import std.io.exception : enforce, IOException;
import std.io.internal.string;

@safe: // TODO nothrow pure

//==============================================================================
/// address family
version (Posix)
    enum AddrFamily : short
    {
        unspecified = AF_UNSPEC,
        IPv4 = AF_INET, /// IPv4
        IPv6 = AF_INET6, /// IPv6
        UNIX = AF_UNIX, /// Unix socket
    }
else version (Windows)
    enum AddrFamily : short
    {
        unspecified = AF_UNSPEC,
        IPv4 = AF_INET, /// IPv4
        IPv6 = AF_INET6, /// IPv6
    }

//==============================================================================
/// IPv4 internet address
struct IPv4Addr
{
@safe:
    ///
    this(ubyte[4] parts...) pure nothrow @nogc
    {
        version(BigEndian)
        {
            addr.s_addr = parts[3] | parts[2] << 8 | parts[1] << 16 | parts[0] << 24;
        }
        else
        {
            addr.s_addr = parts[0] | parts[1] << 8 | parts[2] << 16 | parts[3] << 24;
        }
    }

    ///
    this(in_addr addr) pure nothrow @nogc
    {
        this.addr = addr;
    }

    ///
    string toString() pure nothrow const
    {
        import std.array : appender;

        auto app = appender!string();
        toString(app);
        return app.data;
    }

    ///
    void toString(R)(scope auto ref R r) pure nothrow const
    {
        char[INET_ADDRSTRLEN] buf = void;
        r.put(ipToString(addr, buf));
    }

    /// parse IPv4 address
    static IPv4Addr parse(S)(S s) pure @nogc @trusted if (isStringLike!S)
    {
        IPv4Addr addr;
        enforce!IOException(stringToIP(s, addr.addr), "Failed to parse IPv4 address".String);
        return addr;
    }

    // undocumented for implicit conversion
    .IPAddr IPAddr() const pure nothrow @nogc
    {
        return .IPAddr(this);
    }

    /// implicit conversion to `IPAddr`
    alias IPAddr this;

    /// The any address `0.0.0.0` represents all host network interfaces
    enum any = IPv4Addr(0, 0, 0, 0);

private:
    in_addr addr;
}

///
pure @safe unittest
{
    auto addr = IPv4Addr(127, 0, 0, 1);
    assert(addr.toString == "127.0.0.1");
    assert(IPv4Addr.parse(addr.toString) == addr);
}

//==============================================================================
/// IPv6 internet address
struct IPv6Addr
{
@safe:
    ///
    this(ushort[8] parts...) pure nothrow @nogc
    {
        foreach (i, p; parts)
        {
            version (BigEndian)
                addr.s6_addr16[i] = p;
            else
                addr.s6_addr16[i] = swapEndian(p);
        }
    }

    ///
    this(in6_addr addr) pure nothrow @nogc
    {
        this.addr = addr;
    }

    ///
    string toString() pure nothrow const
    {
        import std.array : appender;

        auto app = appender!string();
        toString(app);
        return app.data;
    }

    ///
    void toString(R)(scope auto ref R r) pure nothrow const @trusted
    {
        char[INET6_ADDRSTRLEN] buf = void;
        r.put(ipToString(addr, buf));
    }

    /// parse IPv6 address
    static IPv6Addr parse(S)(S s) pure @nogc @trusted if (isStringLike!S)
    {
        IPv6Addr addr;
        enforce!IOException(stringToIP(s, addr.addr), "Failed to parse IPv6 address".String);
        return addr;
    }

    // undocumented for implicit conversion
    .IPAddr IPAddr() const pure nothrow @nogc
    {
        return .IPAddr(this);
    }

    /// implicit conversion to `IPAddr`
    alias IPAddr this;

    /// The any address `::` represents all host network interfaces
    enum any = IPv6Addr(0, 0, 0, 0, 0, 0, 0, 0);

private:
    in6_addr addr;
}

///
pure @safe unittest
{
    auto addr = IPv6Addr(0x2001, 0xdb8, 0, 0, 0, 0, 0, 1);
    assert(addr.toString == "2001:db8::1");
    assert(IPv6Addr.parse(addr.toString) == addr);
}

//==============================================================================
/**
   Either an IPv4 or an IPv6 internet address.

   See_also: $(REF IPv4Addr) and $(REF IPv6Addr)
 */
struct IPAddr
{
@safe pure nothrow:
    /// construct from IPv4 address
    this(IPv4Addr addr4) @nogc
    {
        _family = AddrFamily.IPv4;
        this.addr4 = addr4;
    }

    /// construct from IPv4 address
    this(IPv6Addr addr6) @nogc
    {
        _family = AddrFamily.IPv6;
        this.addr6 = addr6;
    }

    ///
    string toString() pure nothrow const
    {
        switch (family)
        {
        case AddrFamily.IPv4:
            return addr4.toString;
        case AddrFamily.IPv6:
            return addr6.toString;
        default:
            assert(0);
        }
    }

    ///
    void toString(R)(scope auto ref R r) pure nothrow const
    {
        switch (family)
        {
        case AddrFamily.IPv4:
            return addr4.toString(r);
        case AddrFamily.IPv6:
            return addr6.toString(r);
        default:
            assert(0);
        }
    }

    /// get address family of the contained IP address
    AddrFamily family() const @nogc
    {
        return _family;
    }

    /// Get the stored IP address specified as type `T`.
    ref inout(T) get(T : IPv4Addr)() inout @nogc
    {
        assert(_family == AddrFamily.IPv4);
        return addr4;
    }

    /// ditto
    ref inout(T) get(T : IPv6Addr)() inout @nogc
    {
        assert(_family == AddrFamily.IPv6);
        return addr6;
    }

private:
    AddrFamily _family;
    union
    {
        IPv4Addr addr4;
        IPv6Addr addr6;
    }
}

///
pure nothrow @safe unittest
{
    immutable addr4 = IPv4Addr(127, 0, 0, 1);
    immutable addr6 = IPv6Addr(0x2001, 0xdb8, 0, 0, 0, 0, 0, 1);

    IPAddr addr = addr4;
    assert(addr.family == AddrFamily.IPv4);
    assert(addr.get!IPv4Addr == addr4);
    assert(addr.toString == "127.0.0.1");

    addr = addr6;
    assert(addr.family == AddrFamily.IPv6);
    assert(addr.get!IPv6Addr == addr6);
    assert(addr.toString == "2001:db8::1");
}

@trusted unittest
{
    import core.exception : AssertError;
    import std.exception : assertThrown, assertNotThrown;

    IPAddr addr;
    assertThrown!AssertError(addr.get!IPv6Addr);
    assertThrown!AssertError(addr.get!IPv4Addr);

    addr = IPAddr(IPv4Addr(127, 0, 0, 1));
    assertThrown!AssertError(addr.get!IPv6Addr);
    assertNotThrown!AssertError(addr.get!IPv4Addr);

    addr = IPAddr(IPv6Addr(0x2001, 0xdb8, 0, 0, 0, 0, 0, 1));
    assertThrown!AssertError(addr.get!IPv4Addr);
    assertNotThrown!AssertError(addr.get!IPv6Addr);
}

/// test whether type `T` is an IP address
enum isIPAddr(T) = is(T == IPv4Addr) || is(T == IPv6Addr) || is(T == IPAddr);

//==============================================================================
/** IPv4 socket address

    The socket address consists of an IPv4Addr and a port number.

    See_also: https://tools.ietf.org/html/rfc791
 */
struct SocketAddrIPv4
{
@safe pure nothrow:
    /// construct socket address from `ip`, and `port`.
    this(IPv4Addr ip, ushort port = 0) @nogc
    {
        sa.sin_family = family;
        this.ip = ip;
        this.port = port;
    }

    /// address family for this socket address
    enum AddrFamily family = AddrFamily.IPv4;

    ///
    string toString() const
    {
        import std.array : appender;

        auto app = appender!string();
        toString(app);
        return app.data;
    }

    ///
    void toString(R)(scope auto ref R r) const
    {
        import core.internal.string : unsignedToTempString;

        ip.toString(r);
        r.put(":");
        r.put(unsignedToTempString(port)[]);
    }

    ///
    bool opEquals()(in SocketAddrIPv4 rhs) const @nogc //REVIEW "in" should be equivalent to "in auto ref" now, right?
    {
        assert(sa.sin_family == AddrFamily.IPv4);
        assert(rhs.sa.sin_family == AddrFamily.IPv4);

        return sa.sin_port == rhs.sa.sin_port &&
            sa.sin_addr.s_addr == rhs.sa.sin_addr.s_addr;
    }

    /// ip for address
    @property IPv4Addr ip() const @nogc
    {
        return IPv4Addr(sa.sin_addr);
    }

    /// ditto
    @property void ip(IPv4Addr ip) @nogc
    {
        sa.sin_addr = ip.addr;
    }

    /// port number for address
    @property ushort port() const @nogc
    {
        version (BigEndian)
            return sa.sin_port;
        else
            return swapEndian(sa.sin_port);
    }

    /// ditto
    @property void port(ushort port) @nogc
    {
        version (BigEndian)
            sa.sin_port = port;
        else
            sa.sin_port = swapEndian(port);
    }

    // return sockaddr and addrlen arguments for C-API calls
    package(std.io.net) inout(Tuple!(sockaddr*, socklen_t)) cargs() @trusted @nogc inout return scope
    {
        auto ret = tuple(cast(const sockaddr*)&sa, sa.sizeof);
        return  * cast(typeof(return) * ) & ret;
    }

    // undocumented for implicit conversion
    .SocketAddr SocketAddr() const @nogc
    {
        return .SocketAddr(this);
    }

    /// implicit conversion to `SocketAddr`
    alias SocketAddr this;

private:
    sockaddr_in sa;
}

///
unittest
{
    auto addr = SocketAddrIPv4(IPv4Addr(127, 0, 0, 1), 8080);
    assert(addr.toString == "127.0.0.1:8080");
    // assert(SocketAddrIPv4.parse(addr.toString) == addr);
}

//==============================================================================
/** IPv6 socket address

    The socket address consists of an IPv6Addr, a port number, a scope
    id, a traffic class, and a flow label.

    See_also: https://tools.ietf.org/html/rfc2553#section-3.3
 */
struct SocketAddrIPv6
{
@safe pure nothrow:
    /// construct socket address from `ip`, `port`, `flowinfo`, and `scope ID`
    this(IPv6Addr ip, ushort port = 0, uint flowinfo = 0, uint scopeId = 0) @nogc
    {
        sa.sin6_family = family;
        this.ip = ip;
        this.port = port;
        this.flowinfo = flowinfo;
        this.scopeId = scopeId;
    }

    /// address family for this socket address
    enum AddrFamily family = AddrFamily.IPv6;

    ///
    string toString() const
    {
        import std.array : appender;

        auto app = appender!string();
        toString(app);
        return app.data;
    }

    ///
    void toString(R)(scope auto ref R r) const
    {
        import core.internal.string : unsignedToTempString;

        r.put("[");
        ip.toString(r);
        r.put("]:");
        r.put(unsignedToTempString(port)[]);
    }

    ///
    bool opEquals()(in SocketAddrIPv6 rhs) const @nogc
    {
        assert(sa.sin6_family == AddrFamily.IPv6);
        assert(rhs.sa.sin6_family == AddrFamily.IPv6);

        return sa.sin6_port == rhs.sa.sin6_port &&
            sa.sin6_flowinfo == rhs.sa.sin6_flowinfo &&
            sa.sin6_addr.s6_addr == rhs.sa.sin6_addr.s6_addr &&
            sa.sin6_scope_id == rhs.sa.sin6_scope_id;
    }

    /// ip for address
    @property IPv6Addr ip() const @nogc
    {
        return IPv6Addr(sa.sin6_addr);
    }

    /// ditto
    @property void ip(IPv6Addr ip) @nogc
    {
        sa.sin6_addr = ip.addr;
    }

    /// port number for address
    @property ushort port() const @nogc
    {
        version (BigEndian)
            return sa.sin6_port;
        else
            return swapEndian(sa.sin6_port);
    }

    /// ditto
    @property void port(ushort port) @nogc
    {
        version (BigEndian)
            sa.sin6_port = port;
        else
            sa.sin6_port = swapEndian(port);
    }

    /// flow label and traffic class for address
    @property uint flowinfo() const @nogc
    {
        return sa.sin6_flowinfo;
    }

    /// ditto
    @property void flowinfo(uint val) @nogc
    {
        sa.sin6_flowinfo = val;
    }

    /// scope ID for address
    @property uint scopeId() const @nogc
    {
        return sa.sin6_scope_id;
    }

    /// ditto
    @property void scopeId(uint id) @nogc
    {
        sa.sin6_scope_id = id;
    }

    // return sockaddr and addrlen arguments for C-API calls
    package(std.io.net) inout(Tuple!(sockaddr*, socklen_t)) cargs() @trusted @nogc inout return scope
    {
        auto ret = tuple(cast(const sockaddr*)&sa, sa.sizeof);
        return  * cast(typeof(return) * ) & ret;
    }

    // undocumented for implicit conversion
    .SocketAddr SocketAddr() const @nogc
    {
        return .SocketAddr(this);
    }

    /// implicit conversion to `SocketAddr`
    alias SocketAddr this;

private:
    sockaddr_in6 sa;
}

///
unittest
{
    auto addr = SocketAddrIPv6(IPv6Addr(0x2001, 0xdb8, 0, 0, 0, 0, 0, 1), 8080);
    assert(addr.toString == "[2001:db8::1]:8080");
    // assert(SocketAddrIPv6.parse(addr.toString) == addr);
}

//==============================================================================
/**
   UNIX domain socket address
 */
version (Posix) struct SocketAddrUnix
{
@safe pure nothrow:
    /// construct socket address from `path`
    this(S)(S path) @nogc if (isStringLike!S)
    {
        import std.utf : byUTF;

        ubyte len;
        sa.sun_family = family;
        foreach (c; path.byUTF!char)
            sa.sun_path[len++] = c;
        sa.sun_path[len++] = '\0';
        static if (is(typeof(sa.sun_len)))
            sa.sun_len = len;
    }

    /// address family for this socket address
    enum AddrFamily family = AddrFamily.UNIX;

    ///
    string toString() const @trusted
    {
        return path.idup;
    }

    ///
    void toString(R)(scope auto ref R r) const
    {
        r.put(path);
    }

    ///
    bool opEquals()(in SocketAddrUnix rhs) const @nogc
    {
        assert(sa.sun_family == AddrFamily.UNIX);
        assert(rhs.sa.sun_family == AddrFamily.UNIX);

        return path == rhs.path;
    }

    // return sockaddr and addrlen arguments for C-API calls
    package(std.io.net) inout(Tuple!(sockaddr*, socklen_t)) cargs() @trusted @nogc inout return scope
    {
        auto ret = tuple(cast(const sockaddr*)&sa, SUN_LEN(sa));
        return  * cast(typeof(return) * ) & ret;
    }

    // undocumented for implicit conversion
    .SocketAddr SocketAddr() const @nogc
    {
        return .SocketAddr(this);
    }

    /// implicit conversion to `SocketAddr`
    alias SocketAddr this;

private:
    const(char)[] path() const @nogc @trusted
    {
        import core.stdc.string : strlen;

        auto p = cast(const char*)&sa.sun_path[0];
        static if (is(typeof(sa.sun_len)))
            return p[0 .. sa.sun_len - 1];
        else
            return p[0 .. strlen(p)];
    }

    sockaddr_un sa;
    static if (is(typeof(sa.sun_len)))
        @property ref ubyte len() @nogc return
        {
            return sa.sun_len;
        }
}

///
version (Posix) unittest
{
    auto addr = SocketAddrUnix("/var/run/unix.sock");
    assert(addr.toString == "/var/run/unix.sock");
}

//==============================================================================
/**
   Generic socket address for families such as IPv4, IPv6, or Unix.
 */
struct SocketAddr
{
@safe:
    ///
    AddrFamily family() pure nothrow const @nogc
    {
        return cast(AddrFamily) storage.ss_family;
    }

    /// Construct generic SocketAddr from IP `addr` and `port`.
    this(IPAddr addr, ushort port = 0) pure nothrow @nogc
    {
        switch (addr.family)
        {
        case AddrFamily.IPv4:
            auto p = cast(SocketAddrIPv4*)&this;
            p.__ctor(addr.get!IPv4Addr, port);
            break;
        case AddrFamily.IPv6:
            auto p = cast(SocketAddrIPv6*)&this;
            p.__ctor(addr.get!IPv6Addr, port);
            break;
        default:
            assert(0, "unimplemented");
        }
    }

    /// Construct generic SocketAddr from specific type `SocketAddrX`.
    this(SocketAddrX)(in SocketAddrX addr) pure nothrow @trusted @nogc
            if (isSocketAddr!SocketAddrX)
    {
        import core.stdc.string : memcpy;

        static assert(addr.sa.sizeof <= storage.sizeof);
        memcpy(&storage, &addr, addr.sizeof);
    }

    ///
    string toString() const
    {
        final switch (family)
        {
        case AddrFamily.unspecified:
            return "unspecified address";
        case AddrFamily.IPv4:
            return (cast(const SocketAddrIPv4*)&this).toString();
        case AddrFamily.IPv6:
            return (cast(const SocketAddrIPv6*)&this).toString();
            version (Posix)
        case AddrFamily.UNIX:
                return (cast(const SocketAddrUnix*)&this).toString();
        }
    }

    ///
    void toString(R)(scope auto ref R r) const
    {
        final switch (family)
        {
        case AddrFamily.unspecified:
            r.put("unspecified address");
            break;
        case AddrFamily.IPv4:
            return (cast(const SocketAddrIPv4*)&this).toString(r);
        case AddrFamily.IPv6:
            return (cast(const SocketAddrIPv6*)&this).toString(r);
            version (Posix)
        case AddrFamily.UNIX:
                return (cast(const SocketAddrUnix*)&this).toString(r);
        }
    }

    /**
       Get specific socket addr type.

       Throws:
         IOException if `family` does not match `SocketAddrX.family`
    */
    ref SocketAddrX get(SocketAddrX)() inout @trusted @nogc
    {
        enforce(family == SocketAddrX.family, "mismatching address family".String);
        return *cast(SocketAddrX*)&this;
    }

    ///
    bool opEquals(SocketAddrX)(in SocketAddrX rhs) pure nothrow const @trusted @nogc
    {
        if (family != rhs.family)
            return false;
        static if (!is(SocketAddrX == SocketAddr))
            return *(cast(const SocketAddrX*)&this) == rhs;
        else
        {
            final switch (family)
            {
            case AddrFamily.unspecified:
                return true;
            case AddrFamily.IPv4:
                return *(cast(const SocketAddrIPv4*)&this) == *(cast(const SocketAddrIPv4*)&rhs);
            case AddrFamily.IPv6:
                return *(cast(const SocketAddrIPv6*)&this) == *(cast(const SocketAddrIPv6*)&rhs);
                version (Posix)
            case AddrFamily.UNIX:
                    return *(cast(const SocketAddrUnix*)&this) == *(
                            cast(const SocketAddrUnix*)&rhs);
            }
        }
    }

    // return sockaddr and addrlen arguments for C-API calls
    package(std.io.net) inout(Tuple!(sockaddr*, socklen_t)) cargs() pure nothrow @trusted @nogc inout return scope
    {
        final switch (family)
        {
        case AddrFamily.unspecified : return typeof(return).init;
        case AddrFamily.IPv4 : return (cast(inout SocketAddrIPv4 * ) & this).cargs;
        case AddrFamily.IPv6 : return (cast(inout SocketAddrIPv6 * ) & this).cargs;
            version (Posix) case AddrFamily.UNIX : return (cast(inout SocketAddrUnix * ) & this)
                .cargs;
        }
    }

private:
    sockaddr_storage storage;
}

///
unittest
{
    immutable addr4 = SocketAddrIPv4(IPv4Addr(127, 0, 0, 1), 1234);
    immutable addr6 = SocketAddrIPv6(IPv6Addr(0x2001, 0xdb8, 0, 0, 0, 0, 0, 1), 1234);
    version (Posix) immutable addru = SocketAddrUnix("/var/run/unix.sock");

    SocketAddr addr = addr4;
    assert(addr.family == AddrFamily.IPv4);
    assert(addr.get!SocketAddrIPv4 == addr4);

    addr = addr6;
    assert(addr.family == AddrFamily.IPv6);
    assert(addr.get!SocketAddrIPv6 == addr6);

    version (Posix)
    {
        addr = addru;
        assert(addr.family == AddrFamily.UNIX);
        assert(addr.get!SocketAddrUnix == addru);
    }
}

//==============================================================================
// uniform socket address construction for generic code

/**
   Construct a `SocketAddrIPv4` from an IPv4 `addr` and `port`.
*/
SocketAddrIPv4 socketAddr(IPv4Addr addr, ushort port = 0) @nogc
{
    return SocketAddrIPv4(addr, port);
}

/**
   Construct a `SocketAddrIPv6` from an IPv6 `addr`, `port`, and
   optionally `flowinfo` and `scopeid`.
*/
SocketAddrIPv6 socketAddr(IPv6Addr addr, ushort port = 0, uint flowinfo = 0, uint scopeId = 0) @nogc
{
    return SocketAddrIPv6(addr, port, flowinfo, scopeId);
}

/**
   Construct a `SocketAddrUnix` from.
*/
SocketAddrUnix socketAddr(S)(S path) @nogc if (isStringLike!S)
{
    return SocketAddrUnix(path);
}

///
unittest
{
    auto sa4 = socketAddr(IPv4Addr(127, 0, 0, 1));
    static assert(is(typeof(sa4) == SocketAddrIPv4));
    auto sa6 = socketAddr(IPv6Addr(0x2001, 0xdb8, 0, 0, 0, 0, 0, 1));
    static assert(is(typeof(sa6) == SocketAddrIPv6));
}

/// test whether type `T` is a socket address
version (Posix)
    enum isSocketAddr(T) = is(T == SocketAddrIPv4) || is(T == SocketAddrIPv6)
            || is(T == SocketAddrUnix) || is(T == SocketAddr);
else version (Windows)
                enum isSocketAddr(T) = is(T == SocketAddrIPv4)
                        || is(T == SocketAddrIPv6) || is(T == SocketAddr);

//==============================================================================
private:

// Won't actually fail with proper buffer size and typed addr, so it'll never set errno and is actually pure
alias pure_inet_ntop = extern (System) const(char)* function(int,scope const(void)*, char*, socklen_t) pure nothrow @nogc; //REVIEW in void* = scope const void*?
// Won't actually fail with proper addr family, so it'll never set errno and is actually pure
alias pure_inet_pton = extern (System) int function(int, scope const(char)*, void*) pure nothrow @nogc;

version (Windows)
{
    extern (Windows) const(char)* inet_ntop(int, in void*, char*, size_t) nothrow @nogc;
    extern (Windows) int inet_pton(int, in char*, void*) nothrow @nogc;
}

const(char)[] ipToString(in in_addr addr, return ref char[INET_ADDRSTRLEN] buf) pure nothrow @nogc @trusted
{
    import core.stdc.string : strlen;

    auto f = cast(pure_inet_ntop)&inet_ntop;
    auto p = f(AF_INET, &addr, buf.ptr, buf.length);
    if (p is null)
        assert(0);
    return p[0 .. strlen(p)];
}

const(char)[] ipToString(in in6_addr addr, return ref char[INET6_ADDRSTRLEN] buf) pure nothrow @nogc @trusted
{
    import core.stdc.string : strlen;

    auto f = cast(pure_inet_ntop)&inet_ntop;
    auto p = f(AF_INET6, &addr, buf.ptr, buf.length);
    if (p is null)
        assert(0);
    return p[0 .. strlen(p)];
}

bool stringToIP(S)(S s, ref in_addr addr) pure nothrow @nogc @trusted
{
    // import std.internal.cstring : tempCString; // impure

    auto f = cast(pure_inet_pton)&inet_pton;
    auto cs = String(s);
    cs ~= '\0';
    immutable res = f(AddrFamily.IPv4, cs[].ptr, &addr);
    if (res == -1)
        assert(0);
    return res == 1;
}

bool stringToIP(S)(S s, ref in6_addr addr) /*pure*/ nothrow @nogc @trusted
{
    // import std.internal.cstring : tempCString; // impure

    auto f = cast(pure_inet_pton)&inet_pton;
    auto cs = String(s);
    cs ~= '\0';
    immutable res = f(AddrFamily.IPv6, cs[].ptr, &addr);
    if (res == -1)
        assert(0);
    return res == 1;
}

version (Posix) ubyte SUN_LEN(in sockaddr_un sun) pure nothrow @nogc @trusted
{
    static if (is(typeof(sun.sun_len)))
        return cast(ubyte)(sun.sun_path.offsetof + sun.sun_len);
    else
    {
        import core.stdc.string : strlen;

        return cast(ubyte)(sun.sun_path.offsetof + strlen(cast(const char*) sun.sun_path.ptr));
    }
}

ushort swapEndian(ushort val) pure nothrow @nogc @safe
{
    return ((val & 0x00FF) << 8) | ((val & 0xFF00) >> 8);
}
