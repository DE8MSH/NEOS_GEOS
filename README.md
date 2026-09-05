# NEOS_GEOS — R46H GEOS/ARM

Native AArch64/Linux reimplementation and compatibility layer for running **GEOS 2.0-era C64 applications on the R46H handheld**. The current hardware-test release is **M15.14 / 1.6.14**.

The project keeps the historical 64 KiB GEOS address space and public KERNAL jump table while implementing graphics, input, D64/VLIR file I/O, menus, dialogs, timing, printer/PDF paths and selected C64 compatibility natively on ARM/Linux. A 6502 executor runs original GEOS applications and calls back into the native GEOS ABI.

## Current status

M15.14 is a hardware-test release focused on the problems seen in real R46H logs with DeskTop, geoWrite and geoPaint:

- 157/157 public GEOS KERNAL vectors have explicit native dispatch paths; current coverage report is 157 full / 0 partial.
- 151/151 documented 6502 opcodes plus the NMOS compatibility opcodes required by tested GEOS applications.
- `OpenDisk` now leaves the historical `r4/r5` disk-name pointers and fixed-length disk-name state expected by DeskTop.
- Dynamic menu callbacks receive the selected menu index in accumulator A before the callback is entered.
- `DoDlgBox` / `RstrFrmDialogue` preserve the real caller PC/SP continuation, including `JMP DoDlgBox` tail-call usage.
- `sysDBData` (`$851D`) drives dialog return values as in the original KERNAL.
- Dialog `DBGETSTRING` uses the actual GetString/UI dispatcher instead of the text dispatcher.
- `PointRecord` reproduces the historical Y=track side effect, including Y=0 for `$00,$FF` empty VLIR records.
- Cooperative callback slicing no longer draws a compatibility-error overlay during a normal slice.
- Joypad/mouse state is published to historical GEOS memory only at safe GEOS yield points, not halfway through a live 6502 callback.
- Failure logging uses RAM ring buffers and only writes detailed traces on failure: CPU history, KERNAL calls, RAM writes, callback/dialog/menu state, pointer state and D64/VLIR state.
- RK817 RTC remains the primary clock; network DNS/SNTP is not run from the GEOS UI loop.

See [STATUS.md](STATUS.md) for known limitations and [HISTORY.md](HISTORY.md) / [CHANGELOG.md](CHANGELOG.md) for release history.

## M15.14 release package

The repository includes the standalone build/install helpers and release records. The packaged source tarball is published as `release/r46h-geos-arm-m15.14.tar.gz`; the standalone incremental builder is `release/build-m15.14-fast.sh`. Verify both with `release/M15.14-SHA256SUMS.txt`.

## Build

For a complete clean build:

```sh
./setup-host.sh
./build.sh
```

For the proven incremental R46H path that reuses an existing Buildroot/hardware cache:

```sh
./scripts/build-m15.14-fast.sh
```

The fast builder expects the previous known-good Buildroot/hardware cache by default under `~/Downloads/r46h-geos-arm-m14.4`. Override `CACHE_ROOT` if yours is elsewhere.

The generated SD image is normally:

```text
output/r46h-geos-arm.img
```

Flash it only after checking the target device carefully:

```sh
sudo ./scripts/install-image.sh output/r46h-geos-arm.img /dev/sdX --yes-really-write
```

## GEOS disk images

**No Berkeley Softworks/GeoWorks GEOS D64, geoWrite/geoPaint binary disk, or uploaded manual PDF is redistributed in this repository.** The user supplies legally obtained disk images on the PC-readable BOOT partition. At boot, the init script mirrors `*.d64` / `*.D64` into `/data/geos/files`.

The project was tested with owner-supplied GEOS 64 D64 images consistent with the CBM Files GEOS 64 1541 set. CBM Files explicitly says those disk images may not be redistributed; therefore this repository records provenance and hashes only. See [docs/SOURCES-AND-HASHES.md](docs/SOURCES-AND-HASHES.md).

Typical BOOT files:

```text
GEOS64.D64       System / DeskTop disk
APPS64.D64       Applications disk containing geoWrite / geoPaint
SPELL64.D64      optional utility disk
WRUTIL64.D64     optional utility disk
```

Use `scripts/verify-d64s.sh` to print hashes of your local copies.

## Test

Host regression suite:

```sh
./test.sh
```

Expected M15.14 baseline:

```text
GEOS/ARM core tests: PASS
6502 opcode coverage: 151/151 official opcodes present
GEOS ABI bridge: 157/157 explicit vectors; 157 full + 0 partial
All host-side GEOS/ARM tests passed.
```

Real media probes are deliberately run against local, user-owned images and are not part of the repository:

```sh
make -C tests probe_real_desktop probe_real_geowrite
./tests/probe_real_desktop /path/to/GEOS64.D64
./tests/probe_real_geowrite /path/to/APPS64.D64
```

## Repository layout

- `src/geos-arm/` — native GEOS/ARM userspace and 6502 compatibility core
- `br2-external/` — Buildroot external tree and R46H rootfs overlay
- `scripts/` — image builder, fast builder, install and verification helpers
- `tests/` — host regression tests and optional real-media probes
- `tools/` — generated ABI/font/resource tooling
- `docs/` — architecture notes, compatibility milestones, source/provenance notes
- `reference/PORT-MAP.md` — port mapping notes; large historical archives are fetched separately

## Licensing and third-party material

The original code in this repository is MIT licensed; see [LICENSE](LICENSE). Historical GEOS, geoWrite, geoPaint, documentation, D64 media and reverse-engineered upstream projects retain their own rights/licensing terms. Source references are listed in `docs/SOURCES-AND-HASHES.md`. Do not assume the project MIT license grants redistribution rights to third-party GEOS binaries or manuals.
