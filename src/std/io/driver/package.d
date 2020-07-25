/**
   Exchangeable driver for std.io

   License: $(HTTP boost.org/LICENSE_1_0.txt, Boost License 1.0).
   Authors: Martin Nowak
   Source: $(PHOBOSSRC std/io/driver/_package.d)
*/
module std.io.driver;

package
{
    import std.io.file : Mode;
    import std.io.net.addr : AddrFamily;
    import std.io.net.socket : SocketType, Protocol, SocketOption;
    import std.io.net.dns : AddrInfo;

    version (Posix)
        import core.sys.posix.sys.socket : sockaddr, socklen_t;
    else version (Windows)
    {
        import core.sys.windows.windef : HANDLE;
        import ws2 = core.sys.windows.winsock2 : sockaddr, socklen_t;
    }
    else
        static assert(0, "unimplemented");
}

/// All handles in std.io are based on this type. The implementation defines how it is used.
struct OpaqueHandle
{
    enum OpaqueHandle INVALID = OpaqueHandle(cast(void*)-1);
    void *handle;
}

/**
   The driver interface used by std.io.

   Swapping this by setting `driver` or `globalDriver` allows to
   exchange the underlying I/O implementation, e.g. for unit-testing
   or to integrate with an asynchronous event loop.

   Note that switching drivers while Files and Sockets are still open is not
   `@safe` and might lead to memory corruption.
 */
interface Driver
{
    // FILE and SOCKET handles cannot be manipulated in @safe code, so most of
    // the Driver's API is @safe.
@safe @nogc:
    /**
       Opaque file handle

       Interpretation left to driver, typically `int` file descriptor
       on Posix systems and `HANDLE` on Windows.
    */
    alias FILE = OpaqueHandle;

    version (Posix)
        alias tchar = char; /// UTF-8 path on Posix, UTF-16 path on Windows
    else version (Windows)
        alias tchar = wchar; /// UTF-8 path on Posix, UTF-16 path on Windows
    else
        static assert(0, "unimplemented");

    shared {
    /**
       Create/open file at `path` in `mode`.

       The path is UTF-8 encoded on Posix and UTF-16 encoded on Windows.
       It is already null-terminated for usage with C APIs.
    */
    FILE createFile( /*in*/ const scope tchar[] path, Mode mode);
    /// Convert platform-specific file handle to `FILE`.
    version (Posix)
        FILE fileFromHandle(int handle);
    else version (Windows)
        FILE fileFromHandle(HANDLE handle);
    /// create/open file at `path` in `mode`
    void closeFile(scope FILE f);
    /// read from file into buffer
    size_t read(scope FILE f, scope ubyte[] buf);
    /// read from file into multiple buffers
    size_t read(scope FILE f, scope ubyte[][] bufs);
    /// write buffer content to file
    size_t write(scope FILE f, /*in*/ const scope ubyte[] buf);
    /// write multiple buffer contents to file
    size_t write(scope FILE f, /*in*/ const scope ubyte[][] bufs);
    /// seek file to offset
    ulong seek(scope FILE f, long offset, int whence);
    }

    /**
       Opaque socket handle

       Interpretation left to driver, typically `int` file descriptor
       on Posix systems and `SOCKET` on Windows.
    */
    alias SOCKET = OpaqueHandle;


    shared {
    /// create socket
    SOCKET createSocket(AddrFamily family, SocketType type, Protocol protocol);
    /// Covert platform-specific socket handle to `SOCKET`.
    version (Posix)
        SOCKET socketFromHandle(int handle);
    else version (Windows)
        SOCKET socketFromHandle(ws2.SOCKET handle);
    /// close socket
    void closeSocket(scope SOCKET s);
    /// bind socket to `addr`
    void bind(scope SOCKET s, const scope sockaddr* addr, socklen_t addrlen) @system;
    /// connect socket to `addr`
    void connect(scope SOCKET s, const scope sockaddr* addr, socklen_t addrlen) @system;
    /// listen for incoming connections
    void listen(scope SOCKET s, uint backlog);
    /// accept an incoming connection, storing remote `addr`
    SOCKET accept(scope SOCKET s, scope sockaddr* addr, ref socklen_t addrlen) @system;
    /// get local (bound) `addr` of socket
    void localAddr( /*in*/ const scope SOCKET s, scope sockaddr* addr, ref socklen_t addrlen) @system;
    /// set socket option, type in `opt` and `optlen` is SocketOptionType!option
    void setSocketOption(scope SOCKET s, SocketOption option, /*in*/ const scope void* opt,
            uint optlen) @system;
    /// get socket option, type in `opt` and `optlen` is SocketOptionType!option
    void getSocketOption( /*in*/ const scope SOCKET s, SocketOption option,
            scope void* opt, socklen_t optlen) @system;
    /// read from socket into buffer, storing source `addr`
    size_t recvFrom(scope SOCKET s, scope ubyte[] buf, scope sockaddr* addr, ref socklen_t addrlen) @system;
    /// read from socket into multiple buffers, storing source `addr`
    size_t recvFrom(scope SOCKET s, scope ubyte[][] bufs, scope sockaddr* addr, ref socklen_t addrlen) @system;
    /// send buffer content to socket and `addr`
    size_t sendTo(scope SOCKET s, /*in*/ const scope ubyte[] buf,
            const scope sockaddr* addr, socklen_t addrlen) @system;
    /// send multiple buffer contents to socket and `addr`
    size_t sendTo(scope SOCKET s, /*in*/ const scope ubyte[][] bufs,
            const scope sockaddr* addr, socklen_t addrlen) @system;
    /// read from socket into buffer
    size_t recv(scope SOCKET s, scope ubyte[] buf);
    /// read from socket into multiple buffers
    size_t recv(scope SOCKET s, scope ubyte[][] bufs);
    /// send buffer content to socket
    size_t send(scope SOCKET s, /*in*/ const scope ubyte[] buf);
    /// send multiple buffer contents to socket
    size_t send(scope SOCKET s, /*in*/ const scope ubyte[][] bufs);

    /**
       Resolve `hostname` using `service`, `family`, `socktype`, and `protocol`
       as hints.  Calls `cb` for each resolved `AddrInfo`. Iteration is
       terminated early when `cb` returns a non-zero value.

       Both `hostname` and `service` are already null-terminated for usage with C APIs.

       Returns: the non-zero value that terminated the iteration or 0 otherwise
    */
    int resolve( /*in*/ const scope char[] hostname, /*in*/ const scope char[] service, AddrFamily family,
            SocketType socktype, Protocol protocol,
            scope int delegate(const scope ref AddrInfo ai) @safe @nogc cb);
    }

    ///
    @safe @nogc unittest
    {
        import std.io.net.addr;
        import std.internal.cstring : tempCString;

        auto res = driver.resolve("localhost", "http", AddrFamily.IPv4,
                SocketType.stream, Protocol.default_, (ref scope ai) {
                    auto addr4 = ai.addr.get!SocketAddrIPv4;
                    assert(addr4.ip == IPv4Addr(127, 0, 0, 1));
                    assert(addr4.port == 80);
                    return 1;
                });
        assert(res == 1);
    }
}

@safe unittest
{
    import std.io.net.addr;
    import std.internal.cstring : tempCString;
    import std.process : environment;

    if (environment.get("SKIP_IPv6_LOOPBACK_TESTS") !is null)
        return;

    auto res = driver.resolve("localhost", "http", AddrFamily.IPv6,
            SocketType.stream, Protocol.default_, (ref scope ai) {
                auto addr6 = ai.addr.get!SocketAddrIPv6;
                assert(addr6.ip == IPv6Addr(0, 0, 0, 0, 0, 0, 0, 1));
                assert(addr6.port == 80);
                return 1;
            });
    assert(res == 1);
}

/**
   Get driver for current thread.

   Will default to `globalDriver` if no per-thread driver
   has been set.
 */
@property shared(Driver) driver() nothrow @trusted @nogc
{
    if (auto d = _driver)
        return cast(shared(Driver)) d;
    else
        return globalDriver;
}

/**
   Set driver for current thread.

   Setting the per-thread driver to `null` will bring `globalDriver`
   in effect again.

   Note that this might invalidate any open File or Socket, hence it is not `@safe`.
 */
@property void driver(shared(Driver) d) nothrow @system @nogc
{
    _driver = cast(Driver) d;
}

/**
   Get default driver for any thread.

   Lazily initializes a SyncDriver if none has been set.
 */
@property shared(Driver) globalDriver() nothrow @trusted @nogc
{
    import core.atomic;
    import std.io.driver.sync : SyncDriver;

    // SyncDriver is stateless, so we can share an immutable instance
    static immutable Driver _syncDriver = new SyncDriver;

    auto d = atomicLoad!(MemoryOrder.raw)(_globalDriver);
    if (d is null)
    {
        // PHOBOS/COMPILER BUG: we need to insert unneccessary casts here
        // see https://issues.dlang.org/show_bug.cgi?id=20359
        cas(&_globalDriver, cast(shared(Driver))null, *cast(shared(Driver)*) &_syncDriver);
        d = atomicLoad!(MemoryOrder.raw)(_globalDriver);
    }
    static if (__VERSION__ < 2077)
        return cast(shared) d;
    else
        return d;
}

/**
   Set default driver for any thread.

   Note that this might invalidate any open File or Socket, hence it is not `@safe`.
 */
@property void globalDriver(shared(Driver) d) nothrow @system @nogc
{
    import core.atomic;

    atomicStore!(MemoryOrder.raw)(_globalDriver, d);
}

// fetch standard handle, 0 = stdin, 1 = stdout, 2 = stderr.
version(Windows)
{
    private HANDLE _getStandardHandle(int fd) @safe @nogc
    {
        pragma(inline, true);
        import core.sys.windows.winbase : GetStdHandle, STD_INPUT_HANDLE,
               STD_OUTPUT_HANDLE, STD_ERROR_HANDLE, INVALID_HANDLE_VALUE;
        if (fd < 0 || fd > 2)
            return INVALID_HANDLE_VALUE;
        static immutable handles = [
            STD_INPUT_HANDLE,
            STD_OUTPUT_HANDLE,
            STD_ERROR_HANDLE,
        ];
        return () @trusted { return GetStdHandle(handles[fd]); }();
    }
}
else version(Posix)
{
    private int _getStandardHandle(int fd) @safe @nogc
    {
        pragma(inline, true);
        // simple sanity check
        if (fd < 0 || fd > 2)
            return -1;
        return fd;
    }
}

/**
   Get standard handles for the process. The items returned by these functions
   are OS handles, and the intention is that you convert them into an
   appropriate IO (e.g. File or Socket) for use.
 */
auto stdin() @safe @nogc
{
    pragma(inline, true);
    return _getStandardHandle(0);
}
/// ditto
auto stdout() @safe @nogc
{
    pragma(inline, true);
    return _getStandardHandle(1);
}
/// ditto
auto stderr() @safe @nogc
{
    pragma(inline, true);
    return _getStandardHandle(2);
}

///
unittest {
    import std.io;
    import std.string : representation;
    // use standard handle
    {
        auto processOut = File(stdout);
        processOut.write("hello, world!\n".representation);
    }
    // note, opening files using OS handles does not close them on destruction.
    auto newProcessOut = File(stdout);
    newProcessOut.write("still there!\n".representation);
}

private:
// cannot store a shared type in TLS :/
Driver _driver;
shared Driver _globalDriver;
