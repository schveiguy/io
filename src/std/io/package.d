/**
   IOs

   This module provides IO traits and interfaces.
   It also imports std.io.file and std.io.net.

   License: $(HTTP boost.org/LICENSE_1_0.txt, Boost License 1.0).
   Authors: Martin Nowak
   Source: $(PHOBOSSRC std/io/_package.d)
*/
module std.io;

///
public import std.io.exception : IOException;

///
public import std.io.file;

///
public import std.io.net;

import std.traits : ReturnType;

// dfmt off
/**
Returns `true` if `IO` is an input. An input/output device must define the
primitive `read` supporting reading into a single and multiple buffers.

Params:
    IO = type to be tested

Returns:
    true if `IO` is an input device
*/
enum isInput(IO) = is(typeof(IO.init) == IO)
    && is(ReturnType!((IO io) @safe{ ubyte[1] buf; return io.read(buf[]); }) == size_t)
    && is(ReturnType!((IO io) @safe{ ubyte[1] buf1, buf2; return io.read(buf1[], buf2[]); }) == size_t)
    && is(ReturnType!((IO io) @safe{ ubyte[][2] bufs; return io.read(bufs); }) == size_t);

/**
Returns `true` if `IO` is an input. An input/output device must define the
primitive `write` supporting writing a single and multiple buffers.

Params:
    IO = type to be tested

Returns:
    true if `IO` is an output device
*/
enum isOutput(IO) = is(typeof(IO.init) == IO)
    && is(ReturnType!((IO io) @safe{ ubyte[1] buf; return io.write(buf[]); }) == size_t)
    && is(ReturnType!((IO io) @safe{ ubyte[1] buf1, buf2; return io.write(buf1[], buf2[]); }) == size_t)
    && is(ReturnType!((IO io) @safe{ ubyte[][2] bufs; return io.write(bufs); }) == size_t);
// dfmt on

/**
Returns `true` if `IO` is an input/output device.

Params:
    IO = type to be tested

Returns:
    true if `IO` is an input/output device

See_also:
    isInput
    isOutput
*/
enum isIO(IO) = isInput!IO && isOutput!IO;

/**
   Input interface for code requiring a polymorphic API.
 */
interface Input
{
@safe @nogc:
    /// read from device into buffer
    size_t read(scope ubyte[] buf) scope;
    /// read from device into multiple buffers
    size_t read(scope ubyte[][] bufs...) scope;
}

/**
   Output interface for code requiring a polymorphic API.
 */
interface Output
{
@safe @nogc:
    /// write buffer content to device
    size_t write(const scope ubyte[] buf) scope;
    /// write multiple buffer contents to device
    size_t write(const scope ubyte[][] bufs...) scope;
}

/**
   Returns an alias sequence `Input` and `Output`, depending on what `IO`
   implements.
 */
template IOInterfaces(IO) if (isInput!IO || isOutput!IO)
{
    import std.meta : AliasSeq;

    static if (isInput!IO && isOutput!IO)
        alias IOInterfaces = AliasSeq!(Input, Output);
    else static if (isInput!IO)
        alias IOInterfaces = AliasSeq!(Input);
    else static if (isOutput!IO)
        alias IOInterfaces = AliasSeq!(Output);
}

///
@safe unittest
{
    import std.meta : AliasSeq;

    static assert(is(IOInterfaces!File == AliasSeq!(Input, Output)));

    static struct In
    {
    @safe:
        size_t read(scope ubyte[]);
        size_t read(scope ubyte[][]...);
    }

    static assert(isInput!In);
    static assert(is(IOInterfaces!In == AliasSeq!(Input)));

    static struct Out
    {
    @safe:
        size_t write(const scope ubyte[]);
        size_t write(const scope ubyte[][]...);
    }

    static assert(isOutput!Out);
    static assert(is(IOInterfaces!Out == AliasSeq!(Output)));

    static struct S
    {
    }

    static assert(!is(IOInterfaces!S));
}

/**
   A template class implementing the supported `IOInterfaces`.
 */
class IOObject(IO) : IOInterfaces!IO
{
@safe @nogc:
    /// construct class from `io`
    this(IO io)
    {
        this.io = io.move;
    }

    static if (isInput!IO)
    {
        /// read from `io`
        size_t read(scope ubyte[] buf) scope
        {
            return io.read(buf);
        }

        /// ditto
        size_t read(scope ubyte[][] bufs...) scope
        {
            return io.read(bufs);
        }
    }

    static if (isOutput!IO)
    {
        /// write to `io`
        size_t write(const scope ubyte[] buf) scope
        {
            return io.write(buf);
        }

        /// ditto
        size_t write(const scope ubyte[][] bufs...) scope
        {
            return io.write(bufs);
        }
    }

    /// forward to `io`
    alias io this;

    /// the contained `IO`
    IO io;
}

/// IFTI construction helper for `IOObject`
IOObject!IO ioObject(IO)(IO io)
{
    return new IOObject!IO(io.move);
}

///
@safe unittest
{
    import std.file : remove;

    /// takes and interface
    static ubyte[] consume(scope Input input, return ubyte[] buf) @safe
    {
        return buf[0 .. input.read(buf)];
    }

    ubyte[4] ping = ['p', 'i', 'n', 'g'];

    File("temp.txt", mode!"w").write(ping[]);
    scope (exit)
        remove("temp.txt");

    auto file = ioObject(File("temp.txt"));
    ubyte[4] buf;
    assert(consume(file, buf[]) == ping[]);

    auto server = UDP.server("localhost", 1234);
    UDP.client("localhost", 1234).write(ping[]);
    /// can be used as scope class
    scope socket = new IOObject!UDP(server.move);
    buf[] = 0;
    assert(consume(socket, buf[]) == ping[]);
}
