# Cross-compile the engine for Windows with mingw-w64, and run its tests under Wine.
#
# This is a smoke test, not a release path. Wine is not Windows -- socket timing,
# select() semantics and error codes all differ -- and a MinGW build uses a
# different CRT and a different C++ ABI than the MSVC builds that ship. The
# windows-2022 CI legs remain the authority for anything released. Nothing here
# may gate a release.
#
# Usage, from the dev container (see tools/devshell.sh):
#
#   cmake -S . -B build-mingw -G Ninja \
#         -DCMAKE_TOOLCHAIN_FILE=cmake/toolchain-mingw-w64.cmake \
#         -DCMAKE_BUILD_TYPE=Release -DQUICKFIX_TESTS=ON
#   cmake --build build-mingw
#   ctest --test-dir build-mingw -L unit --output-on-failure

set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR AMD64)

set(TOOLCHAIN_PREFIX x86_64-w64-mingw32)
set(CMAKE_C_COMPILER   ${TOOLCHAIN_PREFIX}-gcc)
set(CMAKE_CXX_COMPILER ${TOOLCHAIN_PREFIX}-g++)
set(CMAKE_RC_COMPILER  ${TOOLCHAIN_PREFIX}-windres)

set(CMAKE_FIND_ROOT_PATH /usr/${TOOLCHAIN_PREFIX})
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# The load-bearing line. CTest prefixes every registered test command with this,
# so the add_test() calls in src/C++/test/ and test/ run the cross-built .exe
# under Wine with no change to any of them.
find_program(WINE_EXECUTABLE NAMES wine)
if (WINE_EXECUTABLE)
  # Through a wrapper, not wine directly: CTest passes absolute Unix paths as
  # test arguments, and a Windows argument parser reads a leading slash as an
  # option introducer. The wrapper runs winepath over them first.
  set(CMAKE_CROSSCOMPILING_EMULATOR "${CMAKE_CURRENT_LIST_DIR}/wine-runner.sh")
else()
  message(WARNING "wine not found: the build will work, but tests cannot run")
endif()

# Link the runtime statically. Otherwise every .exe needs libstdc++-6.dll and
# libwinpthread-1.dll on Wine's DLL search path, and the failure mode is a
# silent non-zero exit rather than a message naming the missing library.
set(CMAKE_EXE_LINKER_FLAGS_INIT
    "-static-libgcc -static-libstdc++ -Wl,-Bstatic,--whole-archive -lwinpthread -Wl,--no-whole-archive")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "${CMAKE_EXE_LINKER_FLAGS_INIT}")

# Windows 7 and later. Without this mingw's headers default to an older API
# level than the winsock calls in src/C++/Utility.cpp need.
add_compile_definitions(_WIN32_WINNT=0x0601 WINVER=0x0601)

# The GNU assembler's equivalent of MSVC's /bigobj, which src/C++/CMakeLists.txt
# already sets. catch_amalgamated.cpp exceeds the default section limit.
add_compile_options(-Wa,-mbig-obj)

# The cross-built static OpenSSL baked into the dev container image.
if (NOT DEFINED OPENSSL_ROOT_DIR AND EXISTS "$ENV{OPENSSL_MINGW_ROOT}")
  set(OPENSSL_ROOT_DIR "$ENV{OPENSSL_MINGW_ROOT}")
endif()
