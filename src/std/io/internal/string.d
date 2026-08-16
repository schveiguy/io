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
    this(scope const(char)[] s) scope @trusted
    {
        ptr = s.ptr;
        len = cast(uint) s.length;
    }

    this(S)(scope S s) scope if (isStringLike!S)
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
    String clone() return scope //@trusted
    {
        return String(this[]);
    }

    ///
    bool opEquals(scope const ref String s) scope const
    {
        return this[] == s[];
    }

    ///
    int opCmp(scope const ref String s) const
    {
        return __cmp(this[], s[]);
    }

private:

    this(const(char)* ptr, uint len, uint cap) scope
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
    // TODO: we need to enable this, the cloned string snould not be identical.
    //assert(s.ptr != s2.ptr);
}

nothrow @safe @nogc unittest
{
    static void escape(const char[] s) nothrow @safe @nogc
    {
        static const(char)[] cache;
        cache = s;
    }

    scope s = String("Hello");
    version (DIP1000)
        static assert(!__traits(compiles, escape(s[])));
    auto s2 = String("Hello");
    // https://issues.dlang.org/show_bug.cgi?id=17927 :/
    // static assert(!__traits(compiles, escape(s2[])));
}
