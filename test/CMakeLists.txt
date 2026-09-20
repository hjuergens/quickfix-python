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
      # One argument, not three: CTest quotes each argument separately, and
      # `cmd /c "runat.bat" "release" "6680"` trips cmd's quote handling --
      # it answers "The syntax of the command is incorrect."
      add_test(NAME cpp.acceptance
               COMMAND cmd /c "runat.bat $<IF:$<CONFIG:Debug>,debug,release> ${QUICKFIX_AT_PORT}"
               WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}/test)
    endif()
  else()
    # runat.sh starts the acceptor itself, waits for the port, runs the nine
    # Ruby-driven groups, and returns non-zero if any of them failed.
    #
    # Invoked through `sh` rather than as ./runat.sh: on macOS this test failed
    # in 0.02s with a completely empty CTest log -- not one line of output, not
    # even the script's own first error message -- which means the file was never
    # executed at all. Letting sh open it sidesteps whatever refused to exec it,
    # and if the file genuinely cannot be found, sh says so instead of failing
    # mutely.
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

# TEMPORARY diagnostic, to be removed once cpp.acceptance is understood.
#
# On macOS that test fails in 0.01s with a completely empty CTest log -- no
# output from the script, and none from the shell either -- and on Windows with
# only "The syntax of the command is incorrect." Three fixes aimed at the script
# have changed nothing, so this establishes the facts they all assumed:
# does a spawned process's output reach CTest at all, is the file there, and
# does the interpreter run it? Invoking the script with no arguments makes it
# hit its own usage path and exit at once, so this costs no time and starts no
# acceptor.
#
# It always exits 0. The output lands in Testing/Temporary/LastTest.log, which
# the workflow uploads as an artifact when the job fails.
if (TARGET at)
  if (WIN32)
    add_test(NAME diag.acceptance
             COMMAND cmd /c "echo PROBE-START & cd & dir runat.bat setup.bat & echo PROBE-RUN & call runat.bat & echo PROBE-STATUS=%ERRORLEVEL% & exit /b 0"
             WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}/test)
  else()
    add_test(NAME diag.acceptance
             COMMAND sh -c "echo PROBE-START; pwd; ls -l runat.sh setup.sh; for c in sh realpath ruby mktemp; do command -v $c || echo \"PROBE-MISSING: $c\"; done; echo PROBE-RUN; sh runat.sh; echo PROBE-STATUS=$?; exit 0"
             WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}/test)
  endif()
  set_tests_properties(diag.acceptance PROPERTIES LABELS "acceptance" TIMEOUT 120)
endif()

# Temporary diagnostic, not a test of the product. cpp.acceptance fails on macOS
# in 0.01s with a completely empty CTest log and on Windows with a bare "The
# syntax of the command is incorrect", and four attempted fixes have all assumed
# the script was running in the first place. Nothing has established that.
#
# This establishes it. It runs the acceptance script with NO argument, which
# makes it print its usage line and exit 2 immediately -- so if that line does
# not appear, the script never executed, and the problem is the spawn, not the
# script. It exits 0 either way: the point is the transcript, which lands in
# Testing/Temporary/LastTest.log and is uploaded by the workflow.
if (TARGET at)
  if (WIN32)
    # cmd rejected the previous probe before running any of it, so start from the
    # smallest possible thing: if even this fails, CTest cannot drive cmd here at
    # all and runat.bat was never the problem.
    add_test(NAME diag.acceptance.spawn
             COMMAND cmd /c echo PROBE-START
             WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}/test)
    add_test(NAME diag.acceptance.bat
             COMMAND cmd /c runat.bat
             WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}/test)
    set_tests_properties(diag.acceptance.bat PROPERTIES LABELS "acceptance" TIMEOUT 120)
  else()
    add_test(NAME diag.acceptance.spawn
             # The trace stopped after six statements with no error and no usage
             # line. This run captures it to a file instead of a pipe, so the
             # status is the script's own and not head's, and nothing can be lost
             # to SIGPIPE.
             COMMAND sh -c "echo PROBE-START; sh -x runat.sh >/tmp/qf-trace.txt 2>&1; echo PROBE-STATUS=$?; echo PROBE-TRACE-BEGIN; cat /tmp/qf-trace.txt; echo PROBE-TRACE-END; exit 0"
             WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}/test)
  endif()
  set_tests_properties(diag.acceptance.spawn PROPERTIES LABELS "acceptance" TIMEOUT 120)
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
