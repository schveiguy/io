/**
   Temporary iovec array

   License: $(HTTP boost.org/LICENSE_1_0.txt, Boost License 1.0).
   Authors: Martin Nowak
   Source: $(PHOBOSSRC std/io/internal/_iovec.d)
*/
module std.io.internal.iovec;

version (Posix):
package(std.io):

TempIOVecs tempIOVecs(return scope inout(ubyte[])[] bufs) pure nothrow @nogc @safe
{
    return TempIOVecs(bufs);
}

struct TempIOVecs
{
@trusted @nogc pure nothrow:
    enum iovec* useStack = () @trusted{ return cast(iovec*) size_t.max; }();

    this(return scope inout(ubyte[])[] bufs)
    {
        import core.exception : onOutOfMemoryError;

        iovec* ptr;
        if (bufs.length > stack.length)
        {
            _ptr = cast(iovec*) pureMalloc(bufs.length * iovec.sizeof);
            if (_ptr is null)
                onOutOfMemoryError;
        }
        else
            _ptr = stack.ptr;
        foreach (i, b; bufs)
            _ptr[i] = iovec(cast(void*) b.ptr, b.length);
        if (_ptr is stack.ptr)
            _ptr = useStack;
        _length = bufs.length;
    }

    ~this() scope
    {
        if (_ptr !is useStack)
            pureFree(_ptr);
        _ptr = null;
    }

    @property inout(iovec*) ptr() inout return scope
    {
        return _ptr is useStack ? stack.ptr : _ptr;
    }

    @property size_t length() const scope
    {
        return _length;
    }

    @disable this();
    @disable this(this);

private:
    import core.memory : pureFree, pureMalloc;
    import core.sys.posix.sys.uio : iovec;

    iovec* _ptr;
    size_t _length;
    iovec[4] stack;
}
