# Cross-compiles the Windows x64 DLL from a Linux or macOS host with LLVM's MSVC-compatible
# driver. The Windows SDK and CRT come from `xwin splat` into .xwin-cache (see README).
#
# Overrides (pass with -D or set in the environment before configuring):
#   LLVM_ROOT  Directory whose bin/ holds clang-cl, llvm-rc, llvm-lib, llvm-mt.
#   LLD_ROOT   Directory whose bin/ holds lld-link. Defaults to LLVM_ROOT.
#   XWIN_DIR   The xwin splat output. Defaults to <repo>/.xwin-cache.
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

# Homebrew keeps llvm and lld keg-only, so neither is on PATH by default on macOS. Linux
# distributions put them on PATH, so the hints are harmless there.
set(_sunrise_llvm_hints)
set(_sunrise_lld_hints)
if(DEFINED ENV{LLVM_ROOT} AND NOT DEFINED LLVM_ROOT)
    set(LLVM_ROOT "$ENV{LLVM_ROOT}")
endif()
if(DEFINED ENV{LLD_ROOT} AND NOT DEFINED LLD_ROOT)
    set(LLD_ROOT "$ENV{LLD_ROOT}")
endif()
if(DEFINED LLVM_ROOT)
    list(APPEND _sunrise_llvm_hints "${LLVM_ROOT}/bin")
endif()
if(DEFINED LLD_ROOT)
    list(APPEND _sunrise_lld_hints "${LLD_ROOT}/bin")
elseif(DEFINED LLVM_ROOT)
    list(APPEND _sunrise_lld_hints "${LLVM_ROOT}/bin")
endif()
if(CMAKE_HOST_APPLE)
    foreach(_prefix /opt/homebrew/opt /usr/local/opt)
        list(APPEND _sunrise_llvm_hints "${_prefix}/llvm/bin")
        list(APPEND _sunrise_lld_hints "${_prefix}/lld/bin" "${_prefix}/llvm/bin")
    endforeach()
endif()

find_program(SUNRISE_CLANG_CL NAMES clang-cl HINTS ${_sunrise_llvm_hints} REQUIRED)
find_program(SUNRISE_LLD_LINK NAMES lld-link HINTS ${_sunrise_lld_hints} REQUIRED)
find_program(SUNRISE_LLVM_LIB NAMES llvm-lib HINTS ${_sunrise_llvm_hints} REQUIRED)
find_program(SUNRISE_LLVM_RC NAMES llvm-rc HINTS ${_sunrise_llvm_hints} REQUIRED)
find_program(SUNRISE_LLVM_MT NAMES llvm-mt HINTS ${_sunrise_llvm_hints})

set(CMAKE_C_COMPILER "${SUNRISE_CLANG_CL}")
set(CMAKE_CXX_COMPILER "${SUNRISE_CLANG_CL}")
set(CMAKE_LINKER "${SUNRISE_LLD_LINK}")
set(CMAKE_AR "${SUNRISE_LLVM_LIB}")
set(CMAKE_RC_COMPILER "${SUNRISE_LLVM_RC}")
if(SUNRISE_LLVM_MT)
    set(CMAKE_MT "${SUNRISE_LLVM_MT}")
endif()

if(NOT DEFINED XWIN_DIR)
    set(XWIN_DIR "${CMAKE_CURRENT_LIST_DIR}/.xwin-cache")
endif()

set(CMAKE_C_FLAGS "-target x86_64-pc-windows-msvc /winsdkdir \"${XWIN_DIR}/sdk\" /vctoolsdir \"${XWIN_DIR}/crt\"" CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS "${CMAKE_C_FLAGS}" CACHE STRING "" FORCE)

set(CMAKE_SHARED_LINKER_FLAGS "/libpath:\"${XWIN_DIR}/crt/lib/x86_64\" /libpath:\"${XWIN_DIR}/sdk/lib/um/x86_64\" /libpath:\"${XWIN_DIR}/sdk/lib/ucrt/x86_64\"" CACHE STRING "" FORCE)
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS}" CACHE STRING "" FORCE)
set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS}" CACHE STRING "" FORCE)

set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
