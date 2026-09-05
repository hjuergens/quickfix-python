"""Post-build acceptance check for an installed quickfix-tls wheel.

Run against an installed wheel, never the source tree - cibuildwheel invokes this as
its test-command, and it is equally usable by hand:

    pip install dist/quickfix_tls-*.whl
    python tools/verify_wheel.py

It fails loudly if the wheel was built without SSL, which is otherwise easy to miss:
the SSL classes exist either way, and only differ in whether constructing one works.
"""

import os
import sys
import tempfile

FAILURES = []


def check(label, fn):
    try:
        fn()
    except Exception as exc:  # noqa: BLE001 - report every failure, do not stop at the first
        FAILURES.append("%s: %s: %s" % (label, type(exc).__name__, exc))
        print("FAIL  %s -> %s: %s" % (label, type(exc).__name__, exc))
    else:
        print("ok    %s" % label)


import quickfix  # noqa: E402


class _App(quickfix.Application):
    def onCreate(self, sessionID): pass
    def onLogon(self, sessionID): pass
    def onLogout(self, sessionID): pass
    def toAdmin(self, message, sessionID): pass
    def fromAdmin(self, message, sessionID): pass
    def toApp(self, message, sessionID): pass
    def fromApp(self, message, sessionID): pass


SESSION_CFG = """[DEFAULT]
ConnectionType={conn}
ReconnectInterval=60
FileStorePath={store}
FileLogPath={log}
StartTime=00:00:00
EndTime=00:00:00
HeartBtInt=30
UseDataDictionary=N
{extra}

[SESSION]
BeginString=FIX.4.4
SenderCompID=VERIFY_SENDER
TargetCompID=VERIFY_TARGET
"""


def _settings(tmp, name, conn, extra):
    store = os.path.join(tmp, name + "_store")
    log = os.path.join(tmp, name + "_log")
    os.makedirs(store, exist_ok=True)
    os.makedirs(log, exist_ok=True)
    path = os.path.join(tmp, name + ".cfg")
    with open(path, "w") as handle:
        handle.write(SESSION_CFG.format(conn=conn, store=store, log=log, extra=extra))
    settings = quickfix.SessionSettings(path)
    return settings, quickfix.FileStoreFactory(settings), quickfix.FileLogFactory(settings)


def main():
    print("quickfix imported from: %s" % quickfix.__file__)
    if "site-packages" not in quickfix.__file__.replace("\\", "/"):
        print("FAIL  refusing to verify: not imported from an installed wheel")
        return 1

    def not_from_source():
        # A source checkout would shadow the wheel and make every check meaningless.
        assert not os.path.exists(os.path.join(os.path.dirname(quickfix.__file__), "..", "quickfix.i"))

    check("imported from installed wheel", not_from_source)

    def message_round_trip():
        import quickfix44

        msg = quickfix44.NewOrderSingle()
        msg.setField(quickfix.ClOrdID("VERIFY-1"))
        msg.setField(quickfix.Symbol("AAPL"))
        msg.setField(quickfix.Side(quickfix.Side_BUY))
        msg.setField(quickfix.OrderQty(100))
        raw = msg.toString()
        assert quickfix.Message(raw).getField(11) == "VERIFY-1", raw

    check("FIX 4.4 message round-trip", message_round_trip)

    def exceptions_translate():
        # Must raise, not abort the interpreter.
        try:
            quickfix.SessionSettings("no-such-file.cfg")
        except quickfix.ConfigError:
            pass
        else:
            raise AssertionError("expected ConfigError")
        try:
            quickfix.Message("not-a-fix-message")
        except quickfix.InvalidMessage:
            pass
        else:
            raise AssertionError("expected InvalidMessage")

    check("exceptions translate to Python", exceptions_translate)

    for name in ("SSLSocketInitiator", "SSLSocketAcceptor",
                 "ThreadedSSLSocketInitiator", "ThreadedSSLSocketAcceptor"):
        check("%s is exposed" % name, lambda n=name: getattr(quickfix, n))

    # The real point of these wheels: SSL compiled in. Without HAVE_SSL the classes
    # still exist but their constructors raise ConfigError("HAVE_SSL not enabled").
    tmp = tempfile.mkdtemp(prefix="quickfix-verify-")

    def ssl_enabled(cls_name, conn, extra=""):
        def run():
            settings, store, log = _settings(tmp, cls_name, conn, extra)
            try:
                getattr(quickfix, cls_name)(_App(), store, settings, log)
            except quickfix.ConfigError as exc:
                if "HAVE_SSL not enabled" in str(exc):
                    raise AssertionError("wheel was built WITHOUT SSL support") from exc
                raise
        return run

    check("SSLSocketInitiator constructs (SSL enabled)",
          ssl_enabled("SSLSocketInitiator", "initiator", "SocketConnectHost=127.0.0.1\nSocketConnectPort=15001"))
    check("ThreadedSSLSocketInitiator constructs (SSL enabled)",
          ssl_enabled("ThreadedSSLSocketInitiator", "initiator", "SocketConnectHost=127.0.0.1\nSocketConnectPort=15002"))
    check("SSLSocketAcceptor constructs (SSL enabled)",
          ssl_enabled("SSLSocketAcceptor", "acceptor", "SocketAcceptPort=15003"))
    check("ThreadedSSLSocketAcceptor constructs (SSL enabled)",
          ssl_enabled("ThreadedSSLSocketAcceptor", "acceptor", "SocketAcceptPort=15004"))

    print()
    if FAILURES:
        print("%d check(s) failed:" % len(FAILURES))
        for failure in FAILURES:
            print("  - %s" % failure)
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
