/**
   Types for Domain Name Resolution.

   Use $(LINK2 ../driver/Driver.resolve.html, `Driver.resolve`) to
   actually resolve a hostname and service.

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
   A single resolved address entry
*/
struct AddrInfo
{
pure nothrow @safe @nogc:
    this(addrinfo ai)
    {
        this.ai = ai;
    }

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
    SocketAddr addr() const @trusted scope
    {
        import core.stdc.string : memcpy;

        SocketAddr addr = void;
        memcpy( & addr, ai.ai_addr, ai.ai_addrlen);
        return addr;
    }

private:
    version (Posix)
        import core.sys.posix.netdb : addrinfo;
    else
        import core.sys.windows.winsock2 : addrinfo;

    addrinfo ai;
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
        sink(signedToTempString(gaiError));
        sink(")");
    }

private:
    String msg;
}
