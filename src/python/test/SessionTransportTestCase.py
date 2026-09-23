"""End-to-end session tests for every transport this package exposes.

Each case starts a real acceptor and initiator on loopback and waits for both
sides to report onLogon, so a transport that cannot complete a FIX session fails
here rather than in someone's production config.

This matters most for the threaded pair: ThreadedSSLSocketInitiator and
ThreadedSSLSocketAcceptor are the reason quickfix-tls exists, and until this test
existed nothing had ever carried a message over one. tools/verify_wheel.py only
constructs them -- and "constructs without throwing" was exactly the check that
passed on Windows while loading a certificate aborted the process.
"""

import faulthandler
import gc
import os
import time
import unittest

import quickfix as fix

# These cases have segfaulted on macOS and Windows *after* the session is
# established and the test has passed -- i.e. during interpreter shutdown. The
# fault handler turns that into a stack trace instead of an empty log.
faulthandler.enable(all_threads=True)

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
CERT_DIR = os.path.join(REPO_ROOT, "bin", "cfg", "certs")

# Each case binds its own port: they run in one process, and a socket left in
# TIME_WAIT by the previous case would otherwise make the next one flaky.
BASE_PORT = int(os.environ.get("QUICKFIX_TEST_SSL_PORT", "19876"))

# Presence of the symbols proves nothing about SSL support: without HAVE_SSL the
# transports still exist, as stubs from src/swig/SSLStubs.h whose constructors
# throw ConfigError("HAVE_SSL not enabled"). The capability can only be probed by
# constructing one -- and with real settings, since Acceptor::initialize()
# rejects an empty SessionSettings with a ConfigError of its own.
NO_SSL_DETAIL = "HAVE_SSL not enabled"

SESSION_DEFAULTS = {
    "StartTime": "00:00:00",
    "EndTime": "00:00:00",
    "HeartBtInt": "30",
    "ReconnectInterval": "2",
    "UseDataDictionary": "N",
}


class RecordingApplication(fix.Application):
    def __init__(self):
        super(RecordingApplication, self).__init__()
        self.logged_on = []
        self.logged_out = []

    def onCreate(self, sessionID):
        pass

    def onLogon(self, sessionID):
        self.logged_on.append(sessionID)

    def onLogout(self, sessionID):
        self.logged_out.append(sessionID)

    def toAdmin(self, message, sessionID):
        pass

    def fromAdmin(self, message, sessionID):
        pass

    def toApp(self, message, sessionID):
        pass

    def fromApp(self, message, sessionID):
        pass


def make_dictionary(fields):
    d = fix.Dictionary()
    for key, value in fields.items():
        d.setString(key, value)
    return d


class SessionOverTransport(object):
    """Shared body. Subclasses name a transport pair and say whether it is TLS."""

    ACCEPTOR = None
    INITIATOR = None
    USES_TLS = False
    PORT_OFFSET = 0

    def setUp(self):
        for name in (self.ACCEPTOR, self.INITIATOR):
            if not hasattr(fix, name):
                self.skipTest("bindings do not expose %s" % name)

        port = BASE_PORT + self.PORT_OFFSET
        # Distinct comp IDs per case. FIX::Session keeps a process-global registry
        # keyed by SessionID (Session.cpp, s_registered under a static mutex), so
        # cases sharing an ID would have the next one registering while the
        # previous one's sessions are still alive -- which segfaults on macOS and
        # Windows, where teardown timing differs from Linux.
        tag = self.ACCEPTOR[:12].upper()
        self.sender = fix.SessionID("FIX.4.2", "INI_" + tag, "ACC_" + tag)
        self.target = fix.SessionID("FIX.4.2", "ACC_" + tag, "INI_" + tag)

        acceptor_settings = fix.SessionSettings()
        initiator_settings = fix.SessionSettings()

        if self.USES_TLS:
            # Certificate parameters are read only from the DEFAULT section --
            # UtilitySSL::loadSSLCert() calls SessionSettings::get() with no
            # SessionID -- so they must go through settings.set(dict), never
            # settings.set(sessionID, dict).
            acceptor_settings.set(make_dictionary({
                "ServerCertificateFile": os.path.join(CERT_DIR, "127_0_0_1_server.crt"),
                "ServerCertificateKeyFile": os.path.join(CERT_DIR, "127_0_0_1_server.key"),
            }))
            initiator_settings.set(make_dictionary({
                "ClientCertificateFile": os.path.join(CERT_DIR, "127_0_0_1_client.crt"),
                "ClientCertificateKeyFile": os.path.join(CERT_DIR, "127_0_0_1_client.key"),
            }))

        acceptor_settings.set(self.target, make_dictionary(dict(
            SESSION_DEFAULTS,
            ConnectionType="acceptor",
            SocketAcceptPort=str(port),
        )))
        initiator_settings.set(self.sender, make_dictionary(dict(
            SESSION_DEFAULTS,
            ConnectionType="initiator",
            SocketConnectHost="127.0.0.1",
            SocketConnectPort=str(port),
        )))

        self.acceptor_app = RecordingApplication()
        self.initiator_app = RecordingApplication()

        # Kept on self: the Acceptor/Initiator hold only a reference to the store
        # factory, so it must outlive them or ~Session() segfaults on a dangling
        # factory during teardown.
        self.acceptor_store = fix.MemoryStoreFactory()
        self.initiator_store = fix.MemoryStoreFactory()

        self.acceptor = None
        self.initiator = None
        try:
            self.acceptor = getattr(fix, self.ACCEPTOR)(
                self.acceptor_app, self.acceptor_store, acceptor_settings)
            self.initiator = getattr(fix, self.INITIATOR)(
                self.initiator_app, self.initiator_store, initiator_settings)
        except fix.ConfigError as error:
            # Only the stub's own message means "no SSL in this build"; any other
            # ConfigError is a real misconfiguration and must fail the test.
            if getattr(error, "detail", "") != NO_SSL_DETAIL:
                raise
            self.skipTest("bindings built without -DHAVE_SSL=ON")

    def tearDown(self):
        for transport in (self.initiator, self.acceptor):
            if transport is not None:
                transport.stop()

        # Destroy the transports HERE, while the store factories are still
        # referenced by self. Order is the whole point: an Acceptor destroys its
        # Sessions, and ~Session() touches the store its factory made, so the
        # factory has to outlive it.
        #
        # Leaving it to the interpreter does not give that order. unittest drops
        # the test instance when the suite finishes, and PyObject_ClearManagedDict
        # clears attributes in *insertion* order -- self.acceptor_store is created
        # before self.acceptor, so the factory went first and ~Session() ran
        # against freed memory. That is the SIGSEGV seen on macOS and Windows,
        # with FIX::Session::~Session at the top of the faulthandler stack.
        #
        # Dropping everything at once and collecting does not fix it either: that
        # just makes the order arbitrary rather than wrong. Only the transports go
        # here; the factories and applications stay referenced until the instance
        # itself is cleared, which is after this.
        self.initiator = None
        self.acceptor = None
        gc.collect()

    def _wait_until(self, predicate, timeout=10):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if predicate():
                return True
            time.sleep(0.1)
        return False

    def test_logon(self):
        # start() is non-blocking in these bindings -- quickfix.i shadows it to
        # run block() on a background thread -- so both sides come up here and
        # the wait below is what synchronises with them.
        self.acceptor.start()
        self.initiator.start()

        established = self._wait_until(
            lambda: self.acceptor_app.logged_on and self.initiator_app.logged_on
        )

        self.assertTrue(
            established,
            "%s/%s did not establish a session within the timeout"
            % (self.ACCEPTOR, self.INITIATOR),
        )
        self.assertEqual(str(self.initiator_app.logged_on[0]), str(self.sender))
        self.assertEqual(str(self.acceptor_app.logged_on[0]), str(self.target))


class PlainSocketSessionTestCase(SessionOverTransport, unittest.TestCase):
    ACCEPTOR = "SocketAcceptor"
    INITIATOR = "SocketInitiator"
    PORT_OFFSET = 0


class ThreadedSocketSessionTestCase(SessionOverTransport, unittest.TestCase):
    ACCEPTOR = "ThreadedSocketAcceptor"
    INITIATOR = "ThreadedSocketInitiator"
    PORT_OFFSET = 1


class SSLSocketSessionTestCase(SessionOverTransport, unittest.TestCase):
    ACCEPTOR = "SSLSocketAcceptor"
    INITIATOR = "SSLSocketInitiator"
    USES_TLS = True
    PORT_OFFSET = 2


class ThreadedSSLSocketSessionTestCase(SessionOverTransport, unittest.TestCase):
    ACCEPTOR = "ThreadedSSLSocketAcceptor"
    INITIATOR = "ThreadedSSLSocketInitiator"
    USES_TLS = True
    PORT_OFFSET = 3


if __name__ == "__main__":
    unittest.main()
