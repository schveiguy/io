## io [![Build Status](https://travis-ci.org/MartinNowak/io.svg?branch=master)](https://travis-ci.org/MartinNowak/io) [![Build Status](https://ci.appveyor.com/api/projects/status/affs03kt2k1y48o3/branch/master?svg=true)](https://ci.appveyor.com/project/MartinNowak/io) [![codecov](https://codecov.io/gh/MartinNowak/io/branch/master/graph/badge.svg)](https://codecov.io/gh/MartinNowak/io)

## Documentation [std.io](https://martinnowak.github.io/io/std/io)

IOs are thin, OS-independent abstractions over I/O devices.
```d
size_t write(const scope ubyte[] buffer);
size_t read(scope ubyte[] buffer);
```

IOs support [scatter/gather read/write](https://en.wikipedia.org/wiki/Vectored_I/O).
```d
size_t write(const scope ubyte[][] buffers...);
size_t read(scope ubyte[][] buffers...);
```

IOs are `@safe` and `@nogc`.
```d
void read() @safe @nogc
{
    auto f = File(chainPath("tmp", "file.txt"));
    ubyte[128] buf;
    f.read(buf[]);
    // ...
}
```

IOs use exceptions for error handling.
```d
try
    File("");
catch (IOException e)
{}
```

IOs use unique ownership and are [moveable](https://dlang.org/phobos/std_algorithm_mutation.html#.move) but not copyable (Use [refCounted](https://dlang.org/phobos/std_typecons.html#refCounted) for shared ownership).
```d
io2 = io.move;
assert(io2.isOpen);
assert(!io.isOpen);

auto rc = refCounted(io2.move);
auto rc2 = rc;
assert(rc.isOpen);
assert(rc2.isOpen);
```

IOs can be converted to polymorphic interfaces if necessary.
```d
Input input = ioObject(io.move);
```
