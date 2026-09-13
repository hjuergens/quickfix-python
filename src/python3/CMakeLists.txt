set(quickfix_python_VERSION_MAJOR 16)
set(quickfix_python_VERSION_MINOR 0)
set(quickfix_python_VERSION_PATCH 1)
set(quickfix_python_VERSION ${quickfix_python_VERSION_MAJOR}.${quickfix_python_VERSION_MINOR}.${quickfix_python_VERSION_PATCH} )

set(quickfix_python_SOURCES ${PROJECT_SOURCE_DIR}/src/python/QuickfixPython.cpp)
set(quickfix_python_lib_name _${PROJECT_NAME})

add_library(${quickfix_python_lib_name} SHARED  ${quickfix_python_SOURCES})

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
  # CMake's default shared-library suffix on macOS is .dylib, but Python's
  # import machinery only recognizes .so there - without this override the
  # target builds as _quickfix.dylib and `import _quickfix` fails to find it.
  set_target_properties(${quickfix_python_lib_name} PROPERTIES SUFFIX ".so")
endif()

if (MSVC)
  target_compile_options(${quickfix_python_lib_name} PRIVATE /bigobj)
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
