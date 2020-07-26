/// Exceptions used by std.io
module std.io.exception;

import std.io.internal.string;

/// base class for all std.io exceptions
class IOException : Exception
{
    this(String msg) pure nothrow @safe @nogc
    {
        super(null, null, 0);
        this.msg = msg.move;
    }

    override void toString(scope void delegate(const scope char[]) @safe sink) const
    {
        auto nothrowSink = (const scope char[] ch) {
            scope (failure)
                assert(0, "Throwable.toString sink should not throw.");
            sink(ch);
        };
        sink(typeid(this).name);

        if (!msg.empty)
        {
            sink(": ");
            sink(msg[]);
        }
        // I/O specific error message
        ioError(nothrowSink);
        if (info)
        {
            try
            {
                sink("\n----------------");
                foreach (t; info)
                {
                    sink("\n");
                    sink(t);
                }
            }
            catch (Throwable)
            {
                // ignore more errors
            }
        }
    }

protected:
    // The IO error message (errno, gai)
    void ioError(scope void delegate(const scope char[]) nothrow @safe sink) const nothrow @trusted
    {
    }

private:
    String msg;
}

/// exception used by most std.io functions
class ErrnoException : IOException
{
    immutable int errno; /// OS error code

    this(String msg) nothrow @safe @nogc
    {
        super(msg.move);
        version (Windows)
        {
            import core.sys.windows.winbase : GetLastError;

            this.errno = GetLastError;
        }
        else
        {
            import core.stdc.errno : errno;

            this.errno = errno;
        }
    }

protected:
    override void ioError(scope void delegate(const scope char[]) nothrow @safe sink) const nothrow @trusted
    {
        if (!errno)
            return;

        version (Windows)
        {
            import core.sys.windows.winbase;

            char[256] buf = void;
            immutable n = FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
                    null, errno, 0, buf.ptr, buf.length, null);
            sink(": ");
            if (n)
            {
                sink(buf[0 .. n]);
                sink(" ");
            }
        }
        else version (Posix)
        {
            import core.stdc.string : strlen, strerror_r;

            char[128] buf = void;
            const(char)* p;
            version (CRuntime_Glibc)
                p = strerror_r(errno, buf.ptr, buf.length);
            else if (!strerror_r(errno, buf.ptr, buf.length))
                p = buf.ptr;

            sink(": ");
            if (p !is null)
            {
                sink(p[0 .. p.strlen]);
                sink(" ");
            }
        }

        import core.internal.string : signedToTempString;

        sink("(error=");
        sink(signedToTempString(errno));
        sink(")");
    }
}

// TLS storage shared for all exceptions
private void[128] _store;

private T staticException(T)() @nogc if (is(T : Throwable))
{
    // pure hack, what we actually need is @noreturn and allow to call that in pure functions
    static T get()
    {
        static assert(__traits(classInstanceSize, T) <= _store.length,
                T.stringof ~ " is too large for staticError()");

        _store[0 .. __traits(classInstanceSize, T)] = typeid(T).initializer[];
        return cast(T) _store.ptr;
    }

    auto res = (cast(T function() @trusted pure nothrow @nogc)&get)();
    return res;
}

package T enforce(Ex = ErrnoException, T, Args...)(T condition,
        scope String delegate() pure nothrow @safe @nogc msg, auto ref Args args) @trusted @nogc
{
    if (condition)
        return condition;
    throw staticException!Ex.__ctor(msg(), args);
}

package T enforce(Ex = ErrnoException, T, Args...)(T condition, String msg, auto ref Args args) @trusted @nogc
{
    if (condition)
        return condition;
    throw staticException!Ex.__ctor(msg.move, args);
}
