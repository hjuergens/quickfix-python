# quickfix-tls

Prebuilt Python wheels for [QuickFIX](https://github.com/quickfix/quickfix), the C++
FIX (Financial Information eXchange) protocol engine, built with **TLS/SSL transports
enabled**.

## Why this exists

This is an unofficial fork of [quickfix/quickfix](https://github.com/quickfix/quickfix).
It exists to fill two gaps in the official [`quickfix`](https://pypi.org/project/quickfix/)
distribution:

1. **Prebuilt wheels.** The official distribution is published as a source archive only,
   so installing it means compiling the full C++ engine locally — which on Windows needs
   MSVC and, for TLS, an OpenSSL development installation.
2. **TLS transports, ready to use.** These wheels are compiled with `HAVE_SSL` enabled and
   ship the OpenSSL runtime, so `SSLSocketInitiator` / `SSLSocketAcceptor` and the threaded
   variants work out of the box.

It additionally exposes `ThreadedSSLSocketInitiator` and `ThreadedSSLSocketAcceptor`, which
the QuickFIX C++ library implements but has never exposed through its Python bindings.
These are the transports QuickFIX's own C++ examples use for TLS by default.

Both changes are being offered upstream. If they are accepted and the project starts
publishing wheels, this package becomes unnecessary.

## Not installable alongside `quickfix`

This package installs the **same import name** (`quickfix`) as the official distribution.
It is a drop-in replacement, so the two conflict and must not be installed together:

```bash
pip uninstall quickfix
pip install quickfix-tls
```

Your code is unchanged — you still `import quickfix`.

## Supported platforms

Wheels are published for CPython 3.9 - 3.14 on:

| Platform | Architecture | Notes |
|---|---|---|
| Windows | x86_64, arm64 | Python 3.13+ requires **Windows 10 or newer**; 3.12 still supports 8.1. arm64 needs 3.11+ |
| Linux | x86_64, aarch64 | manylinux; musl is not built yet |
| macOS | x86_64, arm64 | |

The Windows floor comes from CPython itself rather than this package - see
[Using Python on Windows](https://docs.python.org/3/using/windows.html). PEP 11 ties
support to Microsoft's lifecycle, so it moves over time.

There are no 32-bit, musllinux, or free-threaded (`t`) wheels. Those install from the
source archive instead, which needs a C++17 compiler and OpenSSL development files.

## Usage

Identical to QuickFIX's documented Python API:

```python
import quickfix

settings = quickfix.SessionSettings("session.cfg")
store    = quickfix.FileStoreFactory(settings)
log      = quickfix.FileLogFactory(settings)

initiator = quickfix.ThreadedSSLSocketInitiator(application, store, settings, log)
initiator.start()
```

See the [QuickFIX documentation](https://quickfixengine.org/) and `README.SSL` in the
repository for the TLS configuration keys (`CertificateFile`, `PrivateKeyFile`,
`CertificateAuthoritiesFile`, `SSLProtocol`, and related settings).

### Choosing a transport

Eight transports are available, in two families:

|         | One thread for all sessions | One thread per session      |
|---------|-----------------------------|-----------------------------|
| Plain   | `SocketInitiator`           | `ThreadedSocketInitiator`   |
|         | `SocketAcceptor`            | `ThreadedSocketAcceptor`    |
| TLS     | `SSLSocketInitiator`        | `ThreadedSSLSocketInitiator`|
|         | `SSLSocketAcceptor`         | `ThreadedSSLSocketAcceptor` |

All eight take the same `(application, storeFactory, settings, logFactory)` constructor
arguments, so switching is a one-line change. There is no configuration key for it: the
threading model is the class you construct, and it cannot be changed on a running object.

The non-threaded classes multiplex every session through a single `select` loop. The threaded
ones spawn a thread per connection, so slow I/O, a TLS handshake or a large message on one
session cannot delay the others — which is why QuickFIX's own C++ examples use the threaded
transports for TLS.

**What threading does and does not buy you in Python.** Your `Application` callbacks are
Python code, and the bindings acquire the GIL to call them, so messages that arrive in
parallel are decoded in parallel but `fromApp` and `fromAdmin` still run one at a time. The
parallelism is in the socket handling, TLS and parsing, not in your handlers. If the handlers
are the bottleneck, hand the work to a queue rather than reaching for the threaded transport.

**`start()` returns immediately** in both families — these bindings run the engine loop on a
background thread — so a script that starts a session and falls off the end will exit. Keep
the process alive yourself:

```python
import time

initiator.start()
try:
    while True:
        time.sleep(1)
finally:
    initiator.stop()
```

### Threading and the GIL

The GIL is a smaller constraint here than it first looks, because most of a FIX engine's work
never touches the interpreter. Socket handling, TLS, message parsing, sequence numbers, store
writes and QuickFIX's own logging all run in C++ threads, and the bindings release the GIL
around every call into C++. A `ThreadedSocketAcceptor` with fifty sessions really does use
fifty OS threads, none of which contend for the interpreter.

The GIL binds in exactly one place: **the callbacks that re-enter Python**. Three classes do
that — `Application`, `Log` and `LogFactory` — and each callback acquires the GIL. So the
serialised portion of your system is the time your handlers spend running, multiplied by the
message rate. Nothing else.

That makes the remedies specific rather than architectural:

1. **Keep handlers short.** Put the message on a `queue.Queue` and return; do the work in a
   consumer thread. This shrinks the only region that serialises, and it is usually enough.
2. **Do not implement `Log` or `LogFactory` in Python.** They are callbacks too, so a Python
   logger takes the GIL *once per log line*, on engine threads, for every session. Use
   `FileLogFactory` or `ScreenLogFactory` and logging never leaves C++. This is easy to do by
   accident and expensive at rate.
3. **Keep blocking work out of handlers.** A database write or an HTTP call inside `fromApp`
   holds the GIL and stalls every session's callbacks, not just the one it belongs to.
4. **Shard across processes** when one interpreter genuinely is not enough. FIX sessions are
   independent, so a process per venue or per session group scales without any GIL
   interaction at all — and it is the only option here that removes the limit rather than
   shrinking it.

**Free-threaded CPython** (the `t` builds) removes the constraint properly, and this package
does build and pass its checks on 3.14t, including a test that hammers `setField`/`getField`
from eight threads at once — the case where SWIG's overloaded dispatch misbehaves without a
GIL ([quickfix#611](https://github.com/quickfix/quickfix/issues/611)). No free-threaded wheels
are published yet, so that path means building from source. Per-object rules still apply:
separate sessions are independent, but a single `Message` is not safe to share across threads.

Subinterpreters (PEP 734) are not a route: this extension keeps process-wide state and is not
built for per-interpreter isolation.

Before optimising, measure which half you are in. If throughput is short of target while
handlers are already trivial, the limit is the engine or the network, and no amount of Python
threading will move it.

## Licence and attribution

QuickFIX is Copyright (c) 2001-2020 Oren Miller and contributors, distributed under the
QuickFIX Software License. This fork carries the same licence; see `LICENSE`. It is not
affiliated with or endorsed by the QuickFIX project.
