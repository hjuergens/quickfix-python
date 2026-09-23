if (WIN32)
add_subdirectory(atrun)
endif()

# Offsets from QUICKFIX_TEST_PORT_BASE; see the comment on that cache variable.
math(EXPR QUICKFIX_AT_PORT "${QUICKFIX_TEST_PORT_BASE} + 0")
math(EXPR QUICKFIX_PT_PORT "${QUICKFIX_TEST_PORT_BASE} + 2")

# at and pt are built in src/, which is added before this directory, so the
# targets already exist. They are absent when QUICKFIX_EXAMPLES is OFF.
if (TARGET at)
  # Linux only, and that is a deliberate limit rather than an oversight. The
  # suite runs there in about a minute; on the other two platforms it never
  # started, and probes established why:
  #
  # Windows -- CTest cannot drive cmd.exe on the runner at all. `cmd /c echo`
  #   fails exactly as `cmd /c runat.bat` does: "The syntax of the command is
  #   incorrect", with no output, in 0.01s. runat.bat itself never runs, so no
  #   amount of quoting or argument shuffling helps. A working Windows test has
  #   to drop cmd entirely -- drive atrun.exe as the CTest command and generate
  #   test/cfg/at.cfg from CMake instead of via setup.bat, which is cmd too.
  #
  # macOS -- the spawn is fine (a probe printed its marker, the working
  #   directory, both scripts as -rwxr-xr-x, and found realpath, ruby and
  #   mktemp). But `sh -x runat.sh` traces exactly six statements and then exits
  #   1 with no error, no syntax complaint and nothing further, on a file that
  #   runs to completion under Linux /bin/sh. Ruled out: the exec bit, the
  #   shebang, output capture, missing tools, SIGPIPE. Unexplained.
  #
  # Both are worth fixing; neither blocks a release, since this suite is
  # pull-request-only and the wheels do not depend on it.
  if (UNIX AND NOT APPLE)
    # runat.sh starts the acceptor itself, waits for the port, runs the nine
    # Ruby-driven groups, and returns non-zero if any of them failed.
    add_test(NAME cpp.acceptance
             COMMAND sh runat.sh ${QUICKFIX_AT_PORT}
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
