if (WIN32)
add_subdirectory(atrun)
endif()

# Offsets from QUICKFIX_TEST_PORT_BASE; see the comment on that cache variable.
math(EXPR QUICKFIX_AT_PORT "${QUICKFIX_TEST_PORT_BASE} + 0")
math(EXPR QUICKFIX_PT_PORT "${QUICKFIX_TEST_PORT_BASE} + 2")

# at and pt are built in src/, which is added before this directory, so the
# targets already exist. They are absent when QUICKFIX_EXAMPLES is OFF.
if (TARGET at)
  if (WIN32)
    if (TARGET atrun)
      # runat.bat is a batch file, and CreateProcess (which CTest uses) cannot
      # launch one, hence cmd /c. It takes the literal directory name debug or
      # release, matching at/atrun's RUNTIME_OUTPUT_DIRECTORY_<CONFIG> -- which
      # maps RelWithDebInfo to "release", so this cannot be $<LOWER_CASE:$<CONFIG>>
      # (that would yield "relwithdebinfo" and hit runat.bat's usage branch).
      add_test(NAME cpp.acceptance
               COMMAND cmd /c runat.bat $<IF:$<CONFIG:Debug>,debug,release> ${QUICKFIX_AT_PORT}
               WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}/test)
    endif()
  else()
    # runat.sh starts the acceptor itself, waits for the port, runs the nine
    # Ruby-driven groups, and returns non-zero if any of them failed.
    add_test(NAME cpp.acceptance
             COMMAND ./runat.sh ${QUICKFIX_AT_PORT}
             WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}/test)
  endif()

  if (TEST cpp.acceptance)
    set_tests_properties(cpp.acceptance PROPERTIES
                         LABELS "acceptance;network"
                         TIMEOUT 900
                         RESOURCE_LOCK quickfix_test_dir)
  endif()
endif()

if (TARGET pt)
  # "-#" must be quoted: an unquoted # starts a CMake comment, which swallows the
  # rest of the line and leaves pt with a bare "-".
  # One test per pass rather than one test running both: a failure in the first
  # pass would otherwise be masked by the second pass's exit status.
  add_test(NAME cpp.perf.offline
           COMMAND pt --quickfix-spec-path ${PROJECT_SOURCE_DIR}/spec "-#" "~[network]"
           WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}/test)
  set_tests_properties(cpp.perf.offline PROPERTIES
                       LABELS "perf"
                       TIMEOUT 900
                       RESOURCE_LOCK quickfix_test_dir)

  add_test(NAME cpp.perf.network
           COMMAND pt --quickfix-spec-path ${PROJECT_SOURCE_DIR}/spec "-#" "[network]"
                      --port ${QUICKFIX_PT_PORT}
           WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}/test)
  set_tests_properties(cpp.perf.network PROPERTIES
                       LABELS "perf;network"
                       TIMEOUT 900
                       RESOURCE_LOCK quickfix_test_dir)
endif()
