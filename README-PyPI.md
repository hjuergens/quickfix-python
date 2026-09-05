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

## Licence and attribution

QuickFIX is Copyright (c) 2001-2020 Oren Miller and contributors, distributed under the
QuickFIX Software License. This fork carries the same licence; see `LICENSE`. It is not
affiliated with or endorsed by the QuickFIX project.
