/**
   Files

   License: $(HTTP boost.org/LICENSE_1_0.txt, Boost License 1.0).
   Authors: Martin Nowak
   Source: $(PHOBOSSRC std/io/net/_package.d)
*/
module std.io.file;

import std.io.exception : enforce;
import std.io.internal.string;
import std.io.driver;

version (Posix)
{
    import core.sys.posix.fcntl;
    import core.sys.posix.stdio : SEEK_SET, SEEK_CUR, SEEK_END;
    import core.sys.posix.sys.uio : readv, writev;
    import core.sys.posix.unistd : close, read, write;
    import std.io.internal.iovec : tempIOVecs;

    enum O_BINARY = 0;
}
else version (Windows)
{
    import core.sys.windows.windef;
    import core.sys.windows.winbase;
    import core.sys.windows.winbase : SEEK_SET=FILE_BEGIN, SEEK_CUR=FILE_CURRENT, SEEK_END=FILE_END;
    import core.stdc.stdio : O_RDONLY, O_WRONLY, O_RDWR, O_APPEND, O_CREAT,
        O_TRUNC, O_BINARY;
}
else
    static assert(0, "unimplemented");

/// File open mode
enum Mode
{
    read = O_RDONLY, /// open for reading only
    write = O_WRONLY, /// open for writing only
    readWrite = O_RDWR, /// open for reading and writing
    append = O_APPEND, /// open in append mode
    create = O_CREAT, /// create file if missing
    truncate = O_TRUNC, /// truncate existing file
    binary = O_BINARY, /// open in binary mode
}

/**
   Convert `fopen` string modes to `Mode` enum values.
   The mode `m` can be one of the following strings.

   $(TABLE
     $(THEAD mode, meaning)
     $(TROW `"r"`, open for reading)
     $(TROW `"r+"`, open for reading)
     $(TROW `"w"`, create or truncate and open for writing)
     $(TROW `"w+"`, create or truncate and open for reading and writing)
     $(TROW `"a"`, create or truncate and open for appending)
     $(TROW `"a+"`, create or truncate and open for reading and appending)
   )

   The mode string can be followed by a `"b"` flag to open files in
   binary mode. This only has an effect on Windows.

   Params:
     m = fopen mode to convert to `Mode` enum

   Macros:
     THEAD=$(TR $(THX $1, $+))
     THX=$(TH $1)$(THX $+)
     TROW=$(TR $(TDX $1, $+))
     TDX=$(TD $1)$(TDX $+)
 */
enum Mode mode(string m) = getMode(m);

///
unittest
{
    assert(mode!"r" == Mode.read);
    assert(mode!"r+" == Mode.readWrite);
    assert(mode!"w" == (Mode.create | Mode.truncate | Mode.write));
    assert(mode!"w+" == (Mode.create | Mode.truncate | Mode.readWrite));
    assert(mode!"a" == (Mode.create | Mode.write | Mode.append));
    assert(mode!"a+" == (Mode.create | Mode.readWrite | Mode.append));
    assert(mode!"rb" == (Mode.read | Mode.binary));
    assert(mode!"r+b" == (Mode.readWrite | Mode.binary));
    assert(mode!"wb" == (Mode.create | Mode.truncate | Mode.write | Mode.binary));
    assert(mode!"w+b" == (Mode.create | Mode.truncate | Mode.readWrite | Mode.binary));
    assert(mode!"ab" == (Mode.create | Mode.write | Mode.append | Mode.binary));
    assert(mode!"a+b" == (Mode.create | Mode.readWrite | Mode.append | Mode.binary));
    static assert(!__traits(compiles, mode!"xyz"));
}

private Mode getMode(string m)
{
    switch (m) with (Mode)
    {
    case "r":
        return read;
    case "r+":
        return readWrite;
    case "w":
        return write | create | truncate;
    case "w+":
        return readWrite | create | truncate;
    case "a":
        return write | create | append;
    case "a+":
        return readWrite | create | append;
    case "rb":
        return read | binary;
    case "r+b":
        return readWrite | binary;
    case "wb":
        return write | create | truncate | binary;
    case "w+b":
        return readWrite | create | truncate | binary;
    case "ab":
        return write | create | append | binary;
    case "a+b":
        return readWrite | create | append | binary;
    default:
        assert(0, "Unknown open mode '" ~ m ~ "'.");
    }
}

/// File seek methods
enum Seek
{
    set = SEEK_SET, /// file offset is set to `offset` bytes from the beginning
    cur = SEEK_CUR, /// file offset is set to current position plus `offset` bytes
    end = SEEK_END, /// file offset is set to the size of the file plus `offset` bytes
}

/**
 */
struct File
{
@safe @nogc:
    /**
       Open a file at `path` with the options specified in `mode`.

       Params:
         path = filesystem path
         mode = file open flags
    */
    this(S)(S path, Mode mode = mode!"r") @trusted if (isStringLike!S)
    {
        closeOnDestroy = true;
        version (Posix)
        {
            import std.internal.cstring : tempCString;

            f = driver.createFile(tempCString(path)[], mode);
        }
        else version (Windows)
        {
            import std.internal.cstring : tempCStringW;

            f = driver.createFile(tempCStringW(path)[], mode);
        }
    }

    /// Wrap an existing open file `handle`. If `takeOwnership` is set to true,
    /// then the descriptor will be closed when the destructor runs.
    version (Posix)
        this(int handle, bool takeOwnership = false)
    {
        closeOnDestroy = false;
        f = driver.fileFromHandle(handle);
    }
    else version (Windows)
        this(HANDLE handle, bool takeOwnership = false)
    {
        closeOnDestroy = false;
        f = driver.fileFromHandle(handle);
    }

    ///
    ~this() scope
    {
        if(closeOnDestroy)
            close();
    }

    // workaround Issue 18000
    void opAssign(scope File rhs) scope
    {
        auto tmp = f;
        () @trusted { f = rhs.f; }();
        rhs.f = tmp;
        rhs.close();
    }

    /// close the file
    void close() scope @trusted
    {
        if (f is Driver.FILE.INVALID)
            return;
        driver.closeFile(f);
        f = Driver.FILE.INVALID;
        closeOnDestroy = false;
    }

    /// return whether file is open
    bool isOpen() const scope
    {
        return f != Driver.FILE.INVALID;
    }

    ///
    unittest
    {
        File f;
        assert(!f.isOpen);
        f = File("LICENSE.txt");
        assert(f.isOpen);
        f.close;
        assert(!f.isOpen);
    }

    /**
       Read from file into buffer.

       Params:
         buf = buffer to read into
       Returns:
         number of bytes read
    */
    size_t read(scope ubyte[] buf) @trusted scope
    {
        return driver.read(f, buf);
    }

    ///
    unittest
    {
        auto f = File("LICENSE.txt");
        ubyte[256] buf = void;
        assert(f.read(buf[]) == buf.length);
    }

    /**
       Read from file into multiple buffers.
       The read will be atomic on Posix platforms.

       Params:
         bufs = buffers to read into
       Returns:
         total number of bytes read
    */
    size_t read(scope ubyte[][] bufs...) @trusted scope
    {
        return driver.read(f, bufs);
    }

    ///
    unittest
    {
        auto f = File("LICENSE.txt");
        ubyte[256] buf = void;
        assert(f.read(buf[$ / 2 .. $], buf[0 .. $ / 2]) == buf.length);
    }

    @("partial reads")
    unittest
    {
        auto f = File("LICENSE.txt");
        ubyte[256] buf = void;
        auto len = f.read(buf[$ / 2 .. $], buf[0 .. $ / 2]);
        while (len == buf.length)
            len = f.read(buf[$ / 2 .. $], buf[0 .. $ / 2]);
        assert(len < buf.length);
    }

    /**
       Write buffer content to file.

       Params:
         buf = buffer to write
       Returns:
         number of bytes written
    */
    size_t write( /*in*/ const scope ubyte[] buf) @trusted scope
    {
        return driver.write(f, buf);
    }

    ///
    unittest
    {
        auto f = File("temp.txt", mode!"w");
        scope (exit)
            remove("temp.txt");
        ubyte[256] buf = 42;
        assert(f.write(buf[]) == buf.length);
    }

    /**
       Write multiple buffers to file.
       The writes will be atomic on Posix platforms.

       Params:
         bufs = buffers to write
       Returns:
         total number of bytes written
    */
    size_t write( /*in*/ const scope ubyte[][] bufs...) @trusted scope
    {
        return driver.write(f, bufs);
    }

    ///
    unittest
    {
        auto f = File("temp.txt", mode!"w");
        scope (exit)
            remove("temp.txt");
        ubyte[256] buf = 42;
        assert(f.write(buf[$ / 2 .. $], buf[0 .. $ / 2]) == buf.length);
    }

    /**
       Reposition the current read and write offset in the file.

       Params:
         offset = positive or negative number of bytes to seek by
         whence = position in the file to seek from
       Returns:
         resulting offset in file
    */
    ulong seek(long offset, Seek whence) scope
    {
        return driver.seek(f, offset, whence);
    }

    ///
    unittest
    {
        auto f = File("LICENSE.txt");
        ubyte[32] buf1 = void, buf2 = void;
        assert(f.read(buf1[]) == buf1.length);

        assert(f.seek(0, Seek.cur) == buf1.length);

        assert(f.seek(-long(buf1.length), Seek.cur) == 0);
        assert(f.read(buf2[]) == buf2.length);
        assert(buf1[] == buf2[]);

        assert(f.seek(0, Seek.set) == 0);
        assert(f.read(buf2[]) == buf2.length);
        assert(buf1[] == buf2[]);

        f.seek(-8, Seek.end);
        assert(f.read(buf2[]) == 8);
        assert(buf1[] != buf2[]);
    }

    /// move operator for file
    File move() return scope nothrow /*pure Issue 18590*/
    {
        auto f = this.f;
        auto cod = closeOnDestroy;
        this.f = Driver.FILE.INVALID;
        this.closeOnDestroy = false;
        return File(f, cod);
    }

    /// not copyable
    @disable this(this);

private:

    this(return scope Driver.FILE f, bool cod) @trusted pure nothrow
    {
        this.f = f;
        this.closeOnDestroy = cod;
    }

    Driver.FILE f = Driver.FILE.INVALID;
    // close when the destructor is run. True normally unless one wraps an
    // existing handle (e.g. stdout).
    bool closeOnDestroy = false;
}

///
unittest
{
    auto f = File("temp.txt", mode!"w");
    scope (exit)
        remove("temp.txt");
    f.write([0, 1]);
}

private:

@safe unittest
{
    import std.io : isIO;

    static assert(isIO!File);

    static File use(File f)
    {
        ubyte[4] buf = [0, 1, 2, 3];
        f.write(buf);
        f.write([4, 5], [6, 7]);
        return f.move;
    }

    auto f = File("temp.txt", mode!"w");
    scope(exit) remove("temp.txt");
    f = use(f.move);
    f = File("temp.txt", Mode.read);
    ubyte[4] buf;
    f.read(buf[]);
    assert(buf[] == [0, 1, 2, 3]);
    ubyte[2] a, b;
    f.read(a[], b[]);
    assert(a[] == [4, 5]);
    assert(b[] == [6, 7]);
    //remove("temp.txt");
}

version (unittest) private void remove(in char[] path) @trusted @nogc
{
    version (Posix)
    {
        import core.sys.posix.unistd : unlink;
        import std.internal.cstring : tempCString;

        enforce(unlink(tempCString(path)) != -1, "unlink failed".String);
    }
    else version (Windows)
    {
        import std.internal.cstring : tempCStringW;

        enforce(DeleteFileW(tempCStringW(path)), "DeleteFile failed".String);
    }
}
