project('io', 'd', default_options: ['optimization=3'], version: '0.3.0', license: 'BSL-1.0' )
common_project_arguments = ['-release'] #, '--d-debug'
add_project_arguments(common_project_arguments, language: 'd')

# semver
version = meson.project_version().split('.')
major_version = version[0].to_int()
minor_version = version[1].to_int()
micro_version = version[2].to_int()

# base
dc = meson.get_compiler('d')

# Source files

sources = [ 'src/std/io/driver/package.d',
            'src/std/io/driver/sync.d',
            'src/std/io/exception.d',
            'src/std/io/file.d',
            'src/std/io/internal/iovec.d',
            'src/std/io/internal/string.d',
            'src/std/io/net/addr.d',
            'src/std/io/net/dns.d',
            'src/std/io/net/package.d',
            'src/std/io/net/socket.d',
            'src/std/io/net/tcp.d',
            'src/std/io/net/udp.d',
            'src/std/io/package.d'
]
inc_dir =  include_directories('src/')

# Compiler and linker flags
common_dflags = []
common_ldflags = []

# library
if host_machine.system() == 'linux'
  common_ldflags += [ '-Wl,-z,relro', '-Wl,-z,now' ]
endif

lib_type = get_option('default_library')
if lib_type == 'shared' 
    libio_soname = 'lib@0@.so.@1@'.format(meson.project_name(), major_version)
    common_ldflags += ['-shared' ]
    if dc.get_id() == 'llvm'
        common_ldflags += [ '-soname', libio_soname ]
    endif 
endif


io_lib = library(meson.project_name(),
    sources,
    include_directories: inc_dir,
    link_args : common_ldflags,
    install: true,
    version: meson.project_version(),
    d_unittest: false
)


io_dep = declare_dependency(
    link_with: [io_lib],
    include_directories: inc_dir,
    dependencies: [],
)

if get_option('run_test')
    configure_file(input: 'LICENSE.txt', output:'LICENSE.txt', copy: true)
    io_test_exe = executable(meson.project_name() + '-test', 
            sources, include_directories: inc_dir, 
            d_unittest: true, 
            link_args: ['-main'],
            d_args: ['-cov'] 
    )
    test(meson.project_name() + '-test', io_test_exe)
endif

# Compat variables for pkgconfig
pkg = import('pkgconfig')
pkg.generate(io_lib,
    description: 'Core I/O functionality.',
    subdirs: 'd/' + meson.project_name(),
    url: 'https://github.com/MartinNowak/io'
)


install_subdir('src/',
    strip_directory : true,
    install_dir: 'include/d/' + meson.project_name(),
)
