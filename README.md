# remote_boot

m1n1 remote booter

## Usage

- `./remoteboot.sh prep` - prepare boot files (requires internet connection)
- `./remoteboot.sh boot /path/to/m1n1-idevice.macho /path/to/monitor-stub.macho` - boot

Preparation needs to be ran once for each model of device.

## Licensing

BSD-3-Clause.

The files in `im4m/*` are signature files and is not a work on art, so it
cannot be protected by copyright. `empty_trustcache.bin` is an empty
instance of the trustcache file format and is essentially API. It is not
protected by copyright.
