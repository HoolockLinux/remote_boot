# remote_boot

m1n1 remote booter for HoolockLinux

## Dependencies

You need [ipsw](https://github.com/blacktop/ipsw) and [irecovery](https://github.com/libimobiledevice/libirecovery).
On Linux, you will also need `util-linux`'s `lsusb`. Other dependencies are vendored as git submodules. For them to
compile however, you must have clang and GNU make installed.

## Usage

- `./remoteboot.sh build` - Compile vendored dependencies
- `./remoteboot.sh prep` - prepare boot files (requires internet connection)
- `./remoteboot.sh boot /path/to/m1n1-idevice.macho /path/to/monitor-stub.macho` - boot
- `./remoteboot.sh firmware` - Download firmware in `/lib/firmware` layout.

Preparation needs to be ran once for each model of device.
The `m1n1-idevice.macho` and `monitor-stub.macho` are generated as part of the
HoolockLinux m1n1 build process, which are mock XNU kernel and mock XNU
watchtower (KPP) respectively.

## Licensing

BSD-3-Clause.

The files in `im4m/*` are signature files and is not a work of art, so it
cannot be protected by copyright. `empty_trustcache.bin` is an empty
instance of the trustcache file format and is essentially API. It is not
protected by copyright.
