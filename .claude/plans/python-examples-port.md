# Port the executor and tradeclient examples to Python

*Status: designed, not implemented. Tracked from [TODO.md](../../TODO.md). Written 2026-09-14 against master at `83c049c7`; re-check the file references before starting.*

## Context

`examples/` ships three C++ demo programs. Only `executor` has a Python counterpart
(`examples/executor/python/executor.py`, 86 lines), it is stale — its
`toAdmin`/`fromAdmin`/`toApp` parameters are in the wrong order, harmless only because the
bodies are empty — and no build file references it, so nothing compiles, installs or runs it.
`tradeclient` and `ordermatch` have no Python at all. The project publishes a Python wheel
(`quickfix-tls`), so Python users are a first-class audience with no runnable example.

The blocker for a faithful port is `FIX::MessageCracker`. All three C++ examples inherit from
it and override typed `onMessage(const FIX42::NewOrderSingle&, ...)` overloads. It is not
wrapped, and it cannot practically be: it dispatches to ~640 typed C++ message classes across
9 FIX versions that SWIG never sees (`grep -c "FIX42::" src/python/QuickfixPython.cpp` → 0).
Python's `quickfix42.NewOrderSingle` is hand-written Python that subclasses `fix.Message` and
sets `MsgType`. So the port ships a **pure-Python cracker** instead — same ergonomics, no SWIG
regeneration (SWIG 4.2.1 is not installed here anyway).

Outcome: `executor` and `tradeclient` runnable from Python, a reusable `crack()` for wheel
users, and a CI job that actually runs them end to end. `ordermatch` is explicitly out of
scope — its matching engine is ~440 lines of C++ business logic with no binding behind it,
making it a rewrite rather than a port.

## Decisions taken

- Port **executor + tradeclient**, not ordermatch.
- Pure-Python cracker module; **no** SWIG change, no regeneration.
- Handler API: `crack()` → `onMessage_<MessageTypeName>(message, sessionID)`, passing the
  **original** `fix.Message` (no re-parse).
- Ports are wired in with `bin/` run scripts **and** a CI smoke test that runs them.

## 1. `src/python3/quickfix_cracker.py` (new)

The name matters: `src/python3/CMakeLists.txt` installs `FILES_MATCHING PATTERN "quickfix*.py"`
into both `lib/python3` and the wheel component, so `quickfix_cracker.py` is packaged with no
build change. Autotools is not glob-driven — add it to `python_DATA` in
[src/python3/Makefile.am:6](../../src/python3/Makefile.am#L6) (which, note, is already missing
`quickfix_fields.py`; mention it, fix it separately).

**MsgType resolution — introspect the `quickfix4x.py` modules, lazily per version.** Parsing
`spec/FIX*.xml` is out (spec files are not in the wheel); a generated static table is out (630
entries that drift from the modules they mirror). Each module is its own table, so per-version
differences fall out for free — `"AB"` is `NewOrderMultileg` in 4.3+ and does not exist in 4.2.
Build `{MsgType: class name}` on first use by instantiating each module-level `Message`
subclass and reading tag 35; cache it. Nested `Group` classes are attributes of message
classes, not module-level, so they are invisible to the scan.

```python
def resolve(message, sessionID=None) -> MessageType | None   # (name, version, module_name, msg_type)

class MessageCracker(object):        # mixin, defines no __init__
    def crack(self, message, sessionID): ...
    def onUnhandledMessage(self, message, sessionID):
        raise fix.UnsupportedMessageType()
```

FIXT.1.1 mirrors [src/C++/MessageCracker.h:51-108](../../src/C++/MessageCracker.h#L51-L108): admin
messages → `quickfixt11`; app messages → `ApplVerID` (1128) from the header, else the session's
default via `fix.Session.lookupSession(sessionID)`, which returns `None` for an unregistered
session (`src/at_application.py:8` already relies on that). Handler names need no normalization
— every class name in all nine modules is already a valid identifier. Say so in the docstring.

Document on `crack()`: **call it from `fromApp`.** Verified at
[src/python/quickfix.i:238-258](../../src/python/quickfix.i#L238-L258) — `fromApp` converts
`UnsupportedMessageType`, `FieldNotFound`, `IncorrectDataFormat` and `IncorrectTagValue` back
to C++; anything else hits `Py_Exit(1)`. `fromAdmin`'s whitelist does not include
`UnsupportedMessageType`, so cracking there without overriding `onUnhandledMessage` kills the
process.

## 2. `examples/executor/python/executor.py` (rewrite)

`class Application(fix.Application, quickfix_cracker.MessageCracker)` — safe because the mixin
has no `__init__`. The six C++ per-version overloads collapse into one
`onMessage_NewOrderSingle` plus a six-row table, because the Python message classes have
no-argument constructors so every field goes through `setField`: 4.0 alone has no
`ExecType`/`LeavesQty`; 4.0–4.2 set `ExecTransType(NEW)`; 4.3+ use `LastQty` not `LastShares`;
4.4/5.0 use `ExecType_TRADE` not `_FILL`. Build the reply as `module.ExecutionReport()`, not a
bare `fix.Message` as the old file did — that is what keeps FIX.5.0 honest (`quickfix50.Message`
sets `BeginString("FIXT.1.1")` + `ApplVerID("7")`).

Keep the rejection path real: `raise fix.IncorrectTagValue(ordType.getTag())` for non-limit
orders, propagating through `crack()` to `fromApp`. **The cracker must not wrap handler calls
in try/except**, or this silently degrades.

`argv[2]` ∈ `{SSL, SSL-ST}` selects `ThreadedSSLSocketAcceptor` / `SSLSocketAcceptor`, else
`SocketAcceptor`, guarded by `hasattr(fix, "SSLSocketAcceptor")` as
[SSLSessionTestCase.py](../../src/python/test/SSLSessionTestCase.py) does. Keep store factory,
settings and log factory alive as locals through `stop()`.

## 3. `examples/tradeclient/python/tradeclient.py` (new)

951 C++ lines → roughly 350 Python. The 22 one-line `query<Field>()` helpers become one
`_ask(prompt, convert)` plus small choice menus; the **12** empty `onMessage` overloads become
two version-independent handlers, `onMessage_ExecutionReport` and `onMessage_OrderCancelReject`
— the clearest payoff of the named-handler design. Drop the MSVC pragmas and the vestigial
`getopt-repl.h` include that `tradeclient.cpp` never uses.

One construction path, two input sources: an `OrderParams` dataclass filled either by prompts
or by `argparse`, consumed by `build_new_order_single` / `build_order_cancel_request` /
`build_cancel_replace_request` / `build_market_data_request`. Interactive is the default so
`bin/run_tradeclient_python3.sh` feels like the C++ one; CI exercises the same builders.

Repeating groups transcribe directly — `module.MarketDataRequest.NoMDEntryTypes()` /
`.NoRelatedSym()` then `md.addGroup(group)`. Use the one-argument `Message.addGroup`, not
`FieldMap.addGroup(tag, group)`.

Non-interactive mode (`--non-interactive --action order|cancel|replace|marketdata --version
--symbol --side --quantity --price --cl-ord-id --count --expect-execution-report
--logon-timeout --response-timeout`): start, **wait for `onLogon`** (exit 2 on timeout), send,
optionally wait for a matching `ClOrdID` in an ExecutionReport (0 success, 3 timeout, 4 on
reject), `stop()`. Callbacks run on QuickFIX threads — synchronize with `threading.Event` + a
lock. Waiting for logon is not optional: [src/python/quickfix.i:83-91](../../src/python/quickfix.i#L83-L91)
shadows `start()` to spawn a thread, so it returns immediately.

Header comment must note that `bin/cfg/tradeclient.cfg` defines only FIX.4.2 sessions, so
`--version` other than 42 raises `SessionNotFound` — same as the C++ example. Do not extend
that shared cfg here.

## 4. Tests and CI

**`src/python/test/MessageCrackerTestCase.py`** (new; reachable from both trees via the
`src/python3/test` symlink), styled after the existing `unittest` cases. Key assertions:
`"AB"` → `NewOrderMultileg` under 4.3 but `None` under 4.2 (this pins the per-module design);
FIXT.1.1 + `ApplVerID("7")` → `quickfix50`; FIXT.1.1 admin → `quickfixt11`; FIXT.1.1 app with
no ApplVerID and no session → `None`, no raise; unknown MsgType → `onUnhandledMessage`;
`assertIs(received, sent)` (pins "no re-parse"); and for all nine modules, every class
instantiates and no two share a MsgType.

Registration: `src/python3/test.sh` has no `set -e`, so only the last line's status is
observed ([TODO.md](../../TODO.md)). Land `set -e` as its own commit first if it is clean; if it
exposes pre-existing failures, do **not** block — append the new test as the last line and
leave `set -e` to the TODO. Either way the test also runs in the new CMake job below, which is
green, unlike the autotools lane.

**New `python_examples` job in [.github/workflows/build_test_cmake.yml](../../.github/workflows/build_test_cmake.yml)**
— a separate job, not a 20-cell matrix addition: ubuntu-latest, `timeout-minutes: 15`,
configure with `-DHAVE_PYTHON3=ON -DQUICKFIX_EXAMPLES=OFF -DQUICKFIX_TESTS=OFF`, build
`--target _quickfix`, run the cracker test, then the smoke script. `PYTHONPATH=lib:src/python3`
per CLAUDE.md — `lib/python3` does not exist without `cmake --install`.

**`test/smoke_python_examples.sh`** (new), modeled on `test/runat.sh`: takes a port (default
6690, clear of at's 6666/6667 and pt's 6668/6669), refuses to run if the port is already open,
generates both cfgs into a `mktemp -d` with stores and logs inside it — never touching
`bin/store`, so reruns can't fail on stale sequence numbers. Start the executor backgrounded,
poll for the port (bailing early if the PID died — that is what `Py_Exit(1)` looks like), then
run the tradeclient under `timeout 90` with `--non-interactive --expect-execution-report`; its
exit code is the assertion. Then assert the executor is **still alive**. On failure, cat both
logs — the autotools lane needed a whole "Show test logs" step added for exactly this reason.
Do not assert the executor's exit status: we SIGTERM it, and a teardown segfault would fail the
run for the wrong reason.

## 5. Run scripts

`bin/run_executor_python3.sh` currently sets `PYTHONPATH=../lib/python3`, which only exists
after `cmake --install`; widen it to `../lib/python3:../lib:../src/python3` so an in-tree build
works. Add `bin/run_tradeclient_python3.sh` plus `run_executor_ssl_python3.sh` /
`run_tradeclient_ssl_python3.sh`, matching the existing naming.

**No `.bat` files.** The existing ones point at MSVC output directories that the C++ examples'
CMakeLists explicitly create; `src/python3/CMakeLists.txt` sets no output directory for
`_quickfix`, and `src/CMakeLists.txt` now skips the extension entirely for MSVC Debug — any
hardcoded path would be wrong on the first configuration someone tried. Put a comment in each
`.sh` telling Windows users to set `PYTHONPATH` or `pip install quickfix-tls`.

## 6. Order of work

1. Cracker + unit test + `python_DATA` entry (everything depends on it; fastest feedback).
2. `set -e` in `test.sh` — separate commit, with the fallback above.
3. Executor port. 4. Tradeclient port. **3 and 4 are independent and can run in parallel.**
5. Smoke script (needs both). 6. Run scripts + CI job.

## Risks

1. **`Py_Exit(1)` on any callback exception** — a typo in a handler kills the process with no
   catchable traceback. Mitigated by the smoke script printing the executor log and asserting
   it survived. Do not "fix" it with a blanket try/except in `crack()`.
2. **Non-blocking `start()`** — wait for `onLogon`, never `sleep 2`.
3. **Teardown segfault** — acceptors hold only a reference to the store factory
   (`SSLSessionTestCase.py`'s comment is load-bearing); keep factories alive through `stop()`.
4. **`bin/cfg/*.cfg` share `FileStorePath=store`** with the C++ examples, so local reruns
   inherit sequence numbers; the smoke test sidesteps this with generated cfgs.
5. **The wheel's `quickfix*.py` glob** ships anything matching it — don't leave scratch files
   named `quickfix_*.py` in `src/python3/`.

## Verification (for whoever implements this later)

- `python3 src/python3/test/MessageCrackerTestCase.py` with `PYTHONPATH=lib:src/python3` — all
  assertions pass, including the nine-module completeness check.
- `./test/smoke_python_examples.sh` locally — exits 0, and prints both logs on failure.
- Manual: `cd bin && ./run_executor_python3.sh` in one shell, `./run_tradeclient_python3.sh` in
  another; enter an order through the menu and see the ExecutionReport come back. Same with
  `run_executor_ssl_python3.sh` / `run_tradeclient_ssl_python3.sh` on an `-DHAVE_SSL=ON` build.
- `make check` (autotools) still behaves as before — it is currently red for an unrelated SSL
  test; this work must not make it redder.
- CI: the new `python_examples` job is green on the PR.

## Out of scope (worth separate changes)

- `ordermatch` — a rewrite, not a port.
- `src/at_application.py` has the same reversed `(self, sessionID, message)` signatures as the
  old executor; harmless but it is exercised by CI.
- `quickfix_fields.py` missing from `python_DATA`.
