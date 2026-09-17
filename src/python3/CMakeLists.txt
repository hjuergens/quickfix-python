set(quickfix_python_VERSION_MAJOR 16)
set(quickfix_python_VERSION_MINOR 0)
set(quickfix_python_VERSION_PATCH 1)
set(quickfix_python_VERSION ${quickfix_python_VERSION_MAJOR}.${quickfix_python_VERSION_MINOR}.${quickfix_python_VERSION_PATCH} )

set(quickfix_python_SOURCES ${PROJECT_SOURCE_DIR}/src/python/QuickfixPython.cpp)
set(quickfix_python_lib_name _${PROJECT_NAME})

if (HAVE_SSL AND WIN32)
  # Loading a certificate hands OpenSSL a FILE* across a CRT boundary, which on
  # Windows needs the applink shim compiled into the module that calls it --
  # otherwise the process dies with "OPENSSL_Uplink: no OPENSSL_Applink". Every
  # example that links OpenSSL already does this; the extension did not, so
  # SSLSocketAcceptor with a ServerCertificateFile could never work there.
  set(applink_SOURCE ${OPENSSL_INCLUDE_DIR}/openssl/applink.c)
endif()

add_library(${quickfix_python_lib_name} SHARED  ${quickfix_python_SOURCES} ${applink_SOURCE})

target_include_directories(${quickfix_python_lib_name} PRIVATE ${PROJECT_SOURCE_DIR} ${PROJECT_SOURCE_DIR}/src ${PROJECT_SOURCE_DIR}/src/C++ ${PROJECT_SOURCE_DIR}/src/swig ${Python3_INCLUDE_DIRS})

if (TARGET Python3::Module)
  target_link_libraries(${quickfix_python_lib_name} ${PROJECT_NAME} Python3::Module)
elseif (TARGET Python3::Python)
  target_link_libraries(${quickfix_python_lib_name} ${PROJECT_NAME} Python3::Python)
else()
  target_link_libraries(${quickfix_python_lib_name} ${PROJECT_NAME} ${PYTHON_LIBRARY})
endif()

if (HAVE_SSL)
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -DHAVE_SSL=1")
  target_link_libraries(${quickfix_python_lib_name} ${PROJECT_NAME} ${OPENSSL_LIBRARIES})
endif()

set_target_properties(${quickfix_python_lib_name} PROPERTIES VERSION ${quickfix_python_VERSION} SOVERSION ${quickfix_python_VERSION_MAJOR} PREFIX "")

if (WIN32)
  set_target_properties(${quickfix_python_lib_name} PROPERTIES SUFFIX ".pyd")
elseif (APPLE)
  # CMake gives a SHARED library .dylib on macOS, and Python will not import
  # that -- only .so. Linux needs no override; its default is already .so.
  set_target_properties(${quickfix_python_lib_name} PROPERTIES SUFFIX ".so")
endif()

if (MSVC)
  target_compile_options(${quickfix_python_lib_name} PRIVATE /bigobj)
endif()

if (WIN32 AND HAVE_SSL)
  # Python 3.8+ resolves an extension module's dependent DLLs from the directory
  # holding the .pyd, from system directories, and from os.add_dll_directory() --
  # never from PATH. So OpenSSL has to sit beside _quickfix.pyd, which is what
  # delvewheel arranges for the wheel and what nothing did for an in-tree build:
  # importing quickfix failed with "DLL load failed while importing _quickfix".
  file(GLOB quickfix_openssl_dlls
       "${OPENSSL_ROOT_DIR}/bin/libssl*.dll"
       "${OPENSSL_ROOT_DIR}/bin/libcrypto*.dll")
  if (quickfix_openssl_dlls)
    add_custom_command(TARGET ${quickfix_python_lib_name} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different ${quickfix_openssl_dlls}
              $<TARGET_FILE_DIR:${quickfix_python_lib_name}>)
  else()
    message(WARNING
      "No OpenSSL DLLs found under '${OPENSSL_ROOT_DIR}/bin'; importing _quickfix "
      "from the build tree will fail unless they are on the DLL search path")
  endif()
endif()

install(TARGETS ${quickfix_python_lib_name} DESTINATION lib/python3)
install(DIRECTORY ${PROJECT_SOURCE_DIR}/src/python3/ DESTINATION lib/python3
        FILES_MATCHING PATTERN "quickfix*.py"
        PATTERN test EXCLUDE)

# Wheel packaging (scikit-build-core installs this component into the archive root).
# EXCLUDE_FROM_ALL keeps it out of a normal `cmake --install`, which still uses lib/python3 above.
install(TARGETS ${quickfix_python_lib_name}
        RUNTIME DESTINATION . COMPONENT python_wheel EXCLUDE_FROM_ALL
        LIBRARY DESTINATION . COMPONENT python_wheel EXCLUDE_FROM_ALL)
install(DIRECTORY ${PROJECT_SOURCE_DIR}/src/python3/ DESTINATION .
        COMPONENT python_wheel EXCLUDE_FROM_ALL
        FILES_MATCHING PATTERN "quickfix*.py"
        PATTERN test EXCLUDE)

# CTest registration. This lives here rather than in src/CMakeLists.txt so it is
# automatically skipped wherever the module is not built (HAVE_PYTHON3=OFF, and
# MSVC Debug, which cannot link the extension at all).
if (QUICKFIX_TESTS AND Python3_EXECUTABLE)
  # The extension lands in lib/ next to libquickfix; the .py wrappers stay in the
  # source tree. lib/python3/ does not exist until `cmake --install`, so neither
  # path can be assumed here.
  if (WIN32)
    # A literal ';' has to be escaped: the ENVIRONMENT property is itself a
    # semicolon-separated CMake list.
    set(quickfix_python_test_env
        "PYTHONPATH=$<TARGET_FILE_DIR:${quickfix_python_lib_name}>\;${PROJECT_SOURCE_DIR}/src/python3")
  else()
    set(quickfix_python_test_env
        "PYTHONPATH=$<TARGET_FILE_DIR:${quickfix_python_lib_name}>:${PROJECT_SOURCE_DIR}/src/python3"
        "LD_LIBRARY_PATH=$<TARGET_FILE_DIR:${PROJECT_NAME}>"
        "DYLD_LIBRARY_PATH=$<TARGET_FILE_DIR:${PROJECT_NAME}>")
  endif()
  list(APPEND quickfix_python_test_env "PYTHONDONTWRITEBYTECODE=1")

  math(EXPR QUICKFIX_PY_SSL_PORT "${QUICKFIX_TEST_PORT_BASE} + 10")

  # Registered one by one, not through test.sh: that script has no `set -e`, so
  # only its last line's status is ever reported.
  # WORKING_DIRECTORY is src/python3 because MessageTestCase.py opens the data
  # dictionaries as ../../spec/FIX4x.xml.
  foreach(case IN ITEMS DataDictionary Dictionary FieldBase MessageStore
                        Message SessionSettings SSLSession)
    add_test(NAME python.${case}
             COMMAND ${Python3_EXECUTABLE}
                     ${PROJECT_SOURCE_DIR}/src/python/test/${case}TestCase.py
             WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}/src/python3)
    set_tests_properties(python.${case} PROPERTIES
                         LABELS "python"
                         TIMEOUT 300
                         ENVIRONMENT "${quickfix_python_test_env}")
  endforeach()

  set_property(TEST python.SSLSession APPEND PROPERTY LABELS "network")
  set_property(TEST python.SSLSession APPEND PROPERTY ENVIRONMENT
               "QUICKFIX_TEST_SSL_PORT=${QUICKFIX_PY_SSL_PORT}")
endif()
