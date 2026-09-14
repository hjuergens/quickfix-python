add_subdirectory(C++)

if( WIN32 OR ${CMAKE_SYSTEM_NAME} STREQUAL "Linux" OR ${CMAKE_SYSTEM_NAME} STREQUAL "Darwin" )

if (QUICKFIX_EXAMPLES)
  add_executable(at at.cpp getopt.c)
  
  target_include_directories(at PRIVATE ${PROJECT_SOURCE_DIR} 
    ${PROJECT_SOURCE_DIR}/src/C++)
    
  target_link_libraries(at ${PROJECT_NAME})
  
  if (NOT WIN32)
  ADD_CUSTOM_TARGET(at_target ALL
                    COMMAND ${CMAKE_COMMAND} -E create_symlink $<TARGET_FILE:at> ${PROJECT_SOURCE_DIR}/test/at)
  else()
  set_target_properties(at PROPERTIES
                        RUNTIME_OUTPUT_DIRECTORY_DEBUG ${PROJECT_SOURCE_DIR}/test/debug/at/
                        RUNTIME_OUTPUT_DIRECTORY_RELEASE ${PROJECT_SOURCE_DIR}/test/release/at/
                        RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO ${PROJECT_SOURCE_DIR}/test/release/at/)
  endif()  
endif()  

if (QUICKFIX_EXAMPLES)
  add_executable(pt pt.cpp
    ${PROJECT_SOURCE_DIR}/src/C++/test/catch_amalgamated.cpp
    ${PROJECT_SOURCE_DIR}/src/C++/test/TestHelper.cpp)

  target_compile_definitions(pt PRIVATE CATCH_AMALGAMATED_CUSTOM_MAIN)

  target_include_directories(pt PRIVATE ${PROJECT_SOURCE_DIR}
    ${PROJECT_SOURCE_DIR}/src/C++
    ${PROJECT_SOURCE_DIR}/src/C++/test)

  target_link_libraries(pt ${PROJECT_NAME})
  
  if (NOT WIN32)
  ADD_CUSTOM_TARGET(pt_target ALL
                    COMMAND ${CMAKE_COMMAND} -E create_symlink $<TARGET_FILE:pt> ${PROJECT_SOURCE_DIR}/test/pt)
  else()
  set_target_properties(pt PROPERTIES
                        RUNTIME_OUTPUT_DIRECTORY_DEBUG ${PROJECT_SOURCE_DIR}/test/debug/pt/
                        RUNTIME_OUTPUT_DIRECTORY_RELEASE ${PROJECT_SOURCE_DIR}/test/release/pt/
                        RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO ${PROJECT_SOURCE_DIR}/test/release/pt/)
  endif()  
endif()  

endif()

if (HAVE_PYTHON3)
# A Debug MSVC build links pythonXY_d.lib through the #pragma comment() in
# pyconfig.h, and no standard CPython ships that debug import library, so the
# link dies with LNK1104. An extension built against the debug ABI is unusable
# from a release interpreter anyway, so skip it rather than fail the build.
# This keys off CMAKE_BUILD_TYPE, which is what the CI matrix passes; a
# multi-config generator driven only by `--build --config Debug` still hits the
# original error.
if (MSVC AND CMAKE_BUILD_TYPE STREQUAL "Debug")
message(STATUS "Skipping the Python 3 extension: MSVC Debug needs pythonXY_d.lib")
else()
add_subdirectory(python3)
endif ()
endif ()
