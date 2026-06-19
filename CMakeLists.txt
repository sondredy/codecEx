# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.20.0)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(codecEx)

target_sources(app PRIVATE src/main.c)

# --- liblc3 compiled from source ---------------------------------------------
# We build liblc3 directly instead of using CONFIG_LIBLC3, because that Kconfig
# option `depends on FPU` and the RISC-V FLPR (VPR) core has no FPU. The sources
# are portable C11 (ARM/NEON paths are #if-guarded out on RISC-V) and the float
# math falls back to the toolchain soft-float library on the FLPR.
set(LIBLC3_DIR ${ZEPHYR_LIBLC3_MODULE_DIR})

if(NOT EXISTS ${LIBLC3_DIR}/include/lc3.h)
  message(FATAL_ERROR "liblc3 module not found at '${LIBLC3_DIR}'. "
                      "Is the liblc3 module present in your west workspace?")
endif()

set(LIBLC3_SRCS
  ${LIBLC3_DIR}/src/attdet.c
  ${LIBLC3_DIR}/src/bits.c
  ${LIBLC3_DIR}/src/bwdet.c
  ${LIBLC3_DIR}/src/energy.c
  ${LIBLC3_DIR}/src/lc3.c
  ${LIBLC3_DIR}/src/ltpf.c
  ${LIBLC3_DIR}/src/mdct.c
  ${LIBLC3_DIR}/src/plc.c
  ${LIBLC3_DIR}/src/sns.c
  ${LIBLC3_DIR}/src/spec.c
  ${LIBLC3_DIR}/src/tables.c
  ${LIBLC3_DIR}/src/tns.c
)

target_include_directories(app PRIVATE ${LIBLC3_DIR}/include)
target_sources(app PRIVATE ${LIBLC3_SRCS})

# Optimize liblc3 for size (-Os): the FLPR executes from RAM, so code size is
# the binding constraint there. LC3plus/HR off (not needed here).
set_source_files_properties(${LIBLC3_SRCS} PROPERTIES COMPILE_OPTIONS
  "-Os;-std=c11;-ffast-math;-DLC3_PLUS=0;-DLC3_PLUS_HR=0;-Wno-array-bounds"
)
