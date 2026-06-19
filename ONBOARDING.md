# Running the LC3 codec on the nRF54LM20 FLPR coprocessor

This project runs the **LC3 audio codec on the FLPR (Fast Lightweight Peripheral
Processor)** — the RISC-V VPR coprocessor on the nRF54LM20 — as a sanity/feasibility
build. The same code also builds for the application core (Cortex-M33).

Board targets:
- `nrf54lm20dk/nrf54lm20a/cpuapp`  — application core (M33, has FPU, fast)
- `nrf54lm20dk/nrf54lm20a/cpuflpr` — FLPR coprocessor (RISC-V RV32E, **no FPU**, soft-float)

Getting the codec onto the FLPR was non-obvious. This doc is the map so the next
person doesn't have to re-derive it.

## TL;DR — build & run on the FLPR

```sh
west build -b nrf54lm20dk/nrf54lm20a/cpuflpr   # sysbuild auto-adds the cpuapp launcher
west flash                                      # flashes merged hex (launcher + FLPR image)
```

Then **watch `/dev/ttyACM1`**, not `ttyACM0`. Expected output:

```
LC3 software codec check (liblc3 / lc3.h)
running on arch: riscv
frame: 160 samples -> 40 LC3 bytes
encoded 320 PCM bytes -> 40 LC3 bytes
decoded 40 LC3 bytes -> 320 PCM bytes
LC3 roundtrip OK. Codec runs on this core (riscv).
```

## The four blockers (and how each is solved)

### 1. Use the right LC3 — source, not the prebuilt blob
nrfxlib's `<sw_codec_lc3.h>` (`CONFIG_SW_CODEC_LC3_T2_SOFTWARE`) is a **prebuilt ARM
Cortex-M33 binary** (`libLC3.a`, hard-float only). It cannot link or run on the
RISC-V FLPR. Use the source-buildable **liblc3** (`<lc3.h>`) instead — portable C11;
its ARM/NEON paths are `#if`-guarded out on RISC-V and the float math falls back to
the toolchain soft-float library.

API is different: caller-allocated contexts (`lc3_*_mem_16k_t`), then
`lc3_setup_encoder/decoder` → `lc3_encode` / `lc3_decode`. See `src/main.c`.

### 2. Bypass the `CONFIG_LIBLC3` FPU gate
`CONFIG_LIBLC3` `depends on FPU`, and the FLPR has no FPU, so the option can't be
enabled there (a Kconfig `depends on` can't be forced from `prj.conf`). Instead we
**compile the liblc3 sources directly** into the app in `CMakeLists.txt`, pulling
them from `${ZEPHYR_LIBLC3_MODULE_DIR}`. Built with `-Os` because the FLPR executes
from RAM, so code size is the binding constraint.

### 3. Memory — the FLPR runs from RAM with a tiny default budget
`CONFIG_XIP` is off on the FLPR: the application core loads the FLPR image from RRAM
into SRAM and the VPR executes everything (code/rodata/data/bss/stack) from SRAM.
Defaults: **96 KB SRAM + 96 KB RRAM**. liblc3 needs ~150 KB SRAM and ~122 KB stored,
so both must be enlarged — and **Partition Manager**, not just devicetree, governs
the split. The enlargement must be applied consistently to **both** sysbuild images.

Memory map we use (nRF54LM20A: 512 KB SRAM, 2036 KB RRAM):

| Region          | Address range            | Size    |
|-----------------|--------------------------|---------|
| FLPR exec SRAM  | `0x20040000`–`0x2007fc00`| 255 KB  |
| cpuapp SRAM     | `0x20000000`–`0x20040000`| 256 KB  |
| FLPR code RRAM  | `0x1bd000`–`0x1fd000`    | 256 KB  |
| cpuapp RRAM     | `0x0`–`0x1bd000`         | 1780 KB |

Constraint: RRAM source ≥ SRAM execution (the launcher copies execution-size bytes
before starting the VPR).

### 4. Boot + console
The VPR does not self-boot. Building for `…/cpuflpr` makes sysbuild auto-add a
`vpr_launcher` (cpuapp, `samples/basic/minimal` + `nordic-flpr` snippet) that loads
and starts the VPR. The FLPR console is `uart30` → the DK's **second VCOM**
(`/dev/ttyACM1`); `ttyACM0` is the cpuapp's `uart20`.

## Files that implement this

| File | Purpose |
|------|---------|
| `src/main.c` | LC3 encode→decode roundtrip via `<lc3.h>` |
| `CMakeLists.txt` | Compiles liblc3 from source (`-Os`), bypassing `CONFIG_LIBLC3` |
| `prj.conf` | `CONFIG_REQUIRES_FULL_LIBC`, stack size, `CONFIG_FPU` (HW float on cpuapp) |
| `boards/nrf54lm20dk_nrf54lm20a_cpuflpr.overlay` | FLPR-side enlarged SRAM + RRAM |
| `sysbuild/vpr_launcher_mem.overlay` | Launcher-side matching memory map |
| `sysbuild.cmake` | Applies launcher overlay **after** the nordic-flpr snippet |

### Why `sysbuild.cmake` + the `_mem` filename
The launcher overlay overrides nodes **created by** the `nordic-flpr` snippet
(`cpuflpr_sram_code_data`, `cpuflpr_code_partition`), so it must be parsed *after* the
snippet. The `sysbuild/<image>.overlay` auto-convention applies *before* the snippet
(parse error: undefined label), so we instead append it via
`vpr_launcher_EXTRA_DTC_OVERLAY_FILE` in `sysbuild.cmake`, and name the file
`vpr_launcher_mem.overlay` so the auto-convention doesn't also pick it up early.

## Caveats / gotchas
- **Slow:** RV32E soft-float MDCTs. Fine for a functional check; profile before any
  real-time audio use on the FLPR.
- **The 256 KB carve-out** of SRAM and RRAM is sized for a standalone test image. In a
  real dual-core product, size it to the actual FLPR workload and keep the
  cpuapp/cpuflpr split coordinated (that's what the two overlays do together).
- A harmless DTC warning (`simple_bus_reg: ... unit address format error`) appears
  because an overlay changes a memory node's `reg` without renaming it. Cosmetic.
- The launcher's RAM region is nominally declared larger than it uses (~6.5 KB actual,
  well below `0x20040000`), so the declared overlap with the FLPR region never bites.

## Toolchain / environment
- NCS `v3.3.1`, toolchain `~/ncs/toolchains/911f4c5c26`.
- If `west`/`ninja` aren't on `PATH`, source the NCS environment (or build from the
  nRF Connect extension). Key env: `ZEPHYR_BASE=~/ncs/v3.3.1/zephyr`,
  `ZEPHYR_TOOLCHAIN_VARIANT=zephyr`, `ZEPHYR_SDK_INSTALL_DIR=<toolchain>/opt/zephyr-sdk`.
