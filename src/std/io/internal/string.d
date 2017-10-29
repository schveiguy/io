/// Helper traits and functions to deal with strings
module std.io.internal.string;

import std.range : ElementEncodingType, isInputRange, isInfinite;
import std.traits : isSomeChar, isSomeString;
import std.bitmanip : bitfields;

/// trait for input ranges of chars
enum isStringLike(S) = (isInputRange!S && !isInfinite!S && isSomeChar!(ElementEncodingType!S))
        || isSomeString!S;

/// @nogc string with unique ownership
struct String
{
nothrow pure @safe @nogc:
    this(const char[] s) @trusted
    {
        ptr = s.ptr;
        len = cast(uint) s.length;
    }

    this(S)(scope S s) if (isStringLike!S)
    {
        this ~= s;
    }

    ~this() scope @trusted
    {
        import core.memory : pureFree;

        if (ptr && cap)
            pureFree(cast(void * ) ptr);
    }

    /// https://issues.dlang.org/show_bug.cgi?id=17927
    const(char)[] opSlice() const return scope @trusted
    {
        return ptr[0 .. len];
    }

    ///
    @property bool empty() const
    {
        return !len;
    }

    ///
    void opOpAssign(string op : "~")(char c) scope
    {
        reserve(1);
        () @trusted
        {
            (cast(char * ) ptr)[len++] = c;
        }
        ();
    }

    ///
    void opOpAssign(string op : "~", S)(scope S s) scope if (isStringLike!S)
    {
        import std.range : hasLength;

        static if (is(ElementEncodingType!S == char) && (hasLength!S || isSomeString!S))
        {
            immutable nlen = s.length;
            reserve(nlen);
            () @trusted
            {
                (cast(char * ) ptr)[len .. len + nlen] = s[];
            }
            ();
            len += nlen;
        }
        else
        {
            import std.utf : byUTF;

            foreach (c; s.byUTF!char)
                this ~= c;
        }
    }

    ///
    void put(S)(scope S s) scope if (isStringLike!S)
    {
        this ~= s;
    }

    /// non-copyable, use `move` or `clone`
    @disable this(this);

    ///
    String move() scope @trusted
    {
        auto optr = ptr;
        auto olen = len;
        auto ocap = cap;
        ptr = null;
        len = 0;
        cap = 0;
        return String(optr, olen, ocap);
    }

    ///
    String clone() scope
    {
        return String(this[]);
    }

    ///
    bool opEquals(in ref String s) const
    {
        return this[] == s[];
    }

    ///
    int opCmp(in ref String s) const
    {
        return __cmp(this[], s[]);
    }

private:

    this(const(char)* ptr, uint len, uint cap)
    {
        this.ptr = ptr;
        this.len = len;
        this.cap = cap;
    }

    void reserve(size_t n) scope @trusted
    {
        import core.exception : onOutOfMemoryError;
        import core.memory : pureMalloc, pureRealloc;

        if (len + n > cap)
        {
            immutable ncap = (len + cast(uint) n) * 3 / 2;
            if (cap)
                ptr = cast(char * ) pureRealloc(cast(char * ) ptr, ncap);
            else if (!len)
                ptr = cast(char * ) pureMalloc(ncap);
            else
            {
                // copy non-owned string on append
                auto nptr = cast(char * ) pureMalloc(ncap);
                if (nptr)
                    nptr[0 .. len] = ptr[0 .. len];
                ptr = nptr;
            }
            cap = ncap;
            if (ptr is null)
                onOutOfMemoryError();
        }
    }

    const(char)* ptr;
    uint len, cap;
}

///
nothrow pure @safe @nogc unittest
{
    auto s = String("Hello");
    assert(s[] == "Hello", s[]);
    s ~= " String";
    assert(s[] == "Hello String", s[]);
    auto s2 = s.clone;
    assert(s == s2);
}

nothrow @safe @nogc unittest
{
    static void escape(const char[] s) nothrow @safe @nogc
    {
        static const(char)[] cache;
        cache = s;
    }

    scope s = String("Hello");
    static assert(!__traits(compiles, escape(s[])));
    auto s2 = String("Hello");
    // https://issues.dlang.org/show_bug.cgi?id=17927 :/
    // static assert(!__traits(compiles, escape(s2[])));
}

package(std.io):

// FIXME: Using the imported std.internal.cstring.tempCStringW produces
// corrupted strings for unknow reasons, copying the definition here works.

auto _tempCString(To = char, From)(From str) if (isStringLike!From)
{
    import std.range : hasLength;
    import std.traits : Unqual;

    alias CF = Unqual!(ElementEncodingType!From);

    auto res = TempCStringBuffer!To.trustedVoidInit(); // expensive to fill _buff[]

    // Note: res._ptr can't point to res._buff as structs are movable.

    To[] p;
    bool p_is_onstack = true;
    size_t i;

    size_t strLength;
    static if (hasLength!From)
    {
        strLength = str.length;
    }
    import std.utf : byUTF;

    static if (isSomeString!From)
    {
        auto r = cast(const(CF)[]) str; // because inout(CF) causes problems with byUTF
        if (r is null) // Bugzilla 14980
        {
            res._ptr = null;
            return res;
        }
    }
    else
        alias r = str;
    To[] q = res._buff;
    foreach (const c; byUTF!(Unqual!To)(r))
    {
        if (i + 1 == q.length)
        {
            p = trustedRealloc(p, i, res._buff, strLength, p_is_onstack);
            p_is_onstack = false;
            q = p;
        }
        q[i++] = c;
    }
    q[i] = 0;
    res._length = i;
    res._ptr = p_is_onstack ? res.useStack : &p[0];
    return res;
}

version (Windows) alias tempCStringW = _tempCString!(wchar, const(char)[]);

private struct TempCStringBuffer(To = char)
{
@trusted pure nothrow @nogc:

    @disable this();
    @disable this(this);
    alias ptr this; /// implicitly covert to raw pointer

    @property inout(To)* buffPtr() inout
    {
        return _ptr == useStack ? _buff.ptr : _ptr;
    }

    @property const(To)* ptr() const
    {
        return buffPtr;
    }

    const(To)[] opIndex() const pure
    {
        return buffPtr[0 .. _length];
    }

    ~this()
    {
        if (_ptr != useStack)
        {
            import core.memory : pureFree;

            pureFree(_ptr);
        }
    }

private:
    enum To* useStack = () @trusted{ return cast(To*) size_t.max; }();

    To* _ptr;
    size_t _length; // length of the string
    version (unittest)
    {
        enum buffLength = 16 / To.sizeof; // smaller size to trigger reallocations
    }
    else
    {
        enum buffLength = 256 / To.sizeof; // production size
    }

    To[buffLength] _buff; // the 'small string optimization'

    static TempCStringBuffer trustedVoidInit()
    {
        TempCStringBuffer res = void;
        return res;
    }
}

private To[] trustedRealloc(To)(To[] buf, size_t i, To[] res, size_t strLength, bool res_is_onstack) @trusted @nogc pure nothrow
{
    pragma(inline, false); // because it's rarely called

    import core.exception : onOutOfMemoryError;
    import core.memory : pureMalloc, pureRealloc;
    import core.stdc.string : memcpy;

    if (res_is_onstack)
    {
        size_t newlen = res.length * 3 / 2;
        if (newlen <= strLength)
            newlen = strLength + 1; // +1 for terminating 0
        auto ptr = cast(To*) pureMalloc(newlen * To.sizeof);
        if (!ptr)
            onOutOfMemoryError();
        memcpy(ptr, res.ptr, i * To.sizeof);
        return ptr[0 .. newlen];
    }
    else
    {
        if (buf.length >= size_t.max / (2 * To.sizeof))
            onOutOfMemoryError();
        const newlen = buf.length * 3 / 2;
        auto ptr = cast(To*) pureRealloc(buf.ptr, newlen * To.sizeof);
        if (!ptr)
            onOutOfMemoryError();
        return ptr[0 .. newlen];
    }
}
