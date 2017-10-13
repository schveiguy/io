/**
   Operations on IOs.

   License: $(HTTP boost.org/LICENSE_1_0.txt, Boost License 1.0).
   Authors: Martin Nowak
   Source: $(PHOBOSSRC std/_io/_ops.d)
*/
module std.io.ops;

import std.io : isInput;

/**
   Read IO Input in chunks using a provided buffer.
 */
struct ByChunk(IO) if (isInput!IO)
{
@safe @nogc:
    /// move contained IO input out
    IO release() scope  /* FIXME: pure nothrow */
    {
        return io.move;
    }

    ///
    bool empty() const pure nothrow
    {
        return !amount;
    }

    ///
    inout(ubyte)[] front() pure nothrow inout return scope
    {
        return buf[0 .. amount];
    }

    ///
    void popFront() scope
    {
        amount = cast(uint) io.read(buf[]);
    }

    ~this() scope
    {
    }

    @disable this(this);

private:
    ubyte[] buf;
    IO io;
    uint amount;
}

/// IFTI construction helper for ByChunk
ByChunk!IO byChunk(IO)(IO io, return scope ubyte[] buf) if (isInput!IO)
{
    return ByChunk!IO(buf, io.move);
}

///
@safe @nogc unittest
{
    import std.io.file;

    ubyte[256] buf = void;
    version (issue_17935_fixed)
    {
        foreach (chunk; File("/dev/random").byChunk(buf[]))
        {
        }
    }
}
