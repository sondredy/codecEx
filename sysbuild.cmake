# Apply our FLPR memory-enlargement overlay to the auto-added vpr_launcher image.
#
# It must be appended to EXTRA_DTC_OVERLAY_FILE so it is parsed AFTER the
# nordic-flpr snippet overlay (which creates the cpuflpr_sram_code_data and
# cpuflpr_code_partition nodes we override).
if(SB_CONFIG_VPR_LAUNCHER)
  sysbuild_cache_set(VAR vpr_launcher_EXTRA_DTC_OVERLAY_FILE APPEND REMOVE_DUPLICATES
                     ${CMAKE_CURRENT_LIST_DIR}/sysbuild/vpr_launcher_mem.overlay)
endif()
