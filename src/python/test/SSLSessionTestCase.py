import os
import time
import unittest

import quickfix as fix

# Presence of the symbols proves nothing about SSL support: without HAVE_SSL the
# transports still exist, as stubs from src/swig/SSLStubs.h whose constructors
# throw ConfigError("HAVE_SSL not enabled"). The capability can only be probed by
# constructing one, which setUp does below -- and it has to be constructed with
# real settings, since Acceptor::initialize() rejects an empty SessionSettings
# with a ConfigError of its own.
HAVE_SSL_SYMBOLS = hasattr(fix, "SSLSocketAcceptor") and hasattr(fix, "SSLSocketInitiator")

NO_SSL_DETAIL = "HAVE_SSL not enabled"

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SPEC_DIR = os.path.join(REPO_ROOT, "spec")
CERT_DIR = os.path.join(REPO_ROOT, "bin", "cfg", "certs")

PORT = int(os.environ.get("QUICKFIX_TEST_SSL_PORT", "19876"))


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


SESSION_DEFAULTS = {
    "StartTime": "00:00:00",
    "EndTime": "00:00:00",
    "HeartBtInt": "30",
    "ReconnectInterval": "2",
    "UseDataDictionary": "N",
}


class SSLSessionTestCase(unittest.TestCase):
    """
    End-to-end check that an SSLSocketAcceptor and SSLSocketInitiator can
    complete a real TLS handshake and a FIX Logon over loopback, using the
    self-signed test certificates under bin/cfg/certs.
    """

    def setUp(self):
        self.sender = fix.SessionID("FIX.4.2", "INITIATOR", "ACCEPTOR")
        self.target = fix.SessionID("FIX.4.2", "ACCEPTOR", "INITIATOR")

        # SSL certificate parameters are only ever read from the DEFAULT
        # section (SessionSettings::get() with no SessionID) by
        # UtilitySSL::loadSSLCert() — they must go through settings.set(dict),
        # not settings.set(sessionID, dict).
        settings = fix.SessionSettings()
        settings.set(make_dictionary({
            "ServerCertificateFile": os.path.join(CERT_DIR, "127_0_0_1_server.crt"),
            "ServerCertificateKeyFile": os.path.join(CERT_DIR, "127_0_0_1_server.key"),
        }))
        settings.set(self.target, make_dictionary(dict(
            SESSION_DEFAULTS,
            ConnectionType="acceptor",
            SocketAcceptPort=str(PORT),
        )))

        initiator_settings = fix.SessionSettings()
        initiator_settings.set(make_dictionary({
            "ClientCertificateFile": os.path.join(CERT_DIR, "127_0_0_1_client.crt"),
            "ClientCertificateKeyFile": os.path.join(CERT_DIR, "127_0_0_1_client.key"),
        }))
        initiator_settings.set(self.sender, make_dictionary(dict(
            SESSION_DEFAULTS,
            ConnectionType="initiator",
            SocketConnectHost="127.0.0.1",
            SocketConnectPort=str(PORT),
        )))

        self.acceptor_app = RecordingApplication()
        self.initiator_app = RecordingApplication()

        # Kept on self: the Acceptor/Initiator only take a reference to the
        # store factory, so it must outlive them or ~Session() segfaults on
        # a dangling factory during teardown.
        self.acceptor_store = fix.MemoryStoreFactory()
        self.initiator_store = fix.MemoryStoreFactory()

        if not HAVE_SSL_SYMBOLS:
            self.skipTest("bindings expose no SSL transports")

        try:
            self.acceptor = fix.SSLSocketAcceptor(self.acceptor_app, self.acceptor_store, settings)
            self.initiator = fix.SSLSocketInitiator(self.initiator_app, self.initiator_store, initiator_settings)
        except fix.ConfigError as error:
            # Only the stub's own message means "no SSL in this build"; any other
            # ConfigError is a real misconfiguration and must fail the test.
            if getattr(error, "detail", "") != NO_SSL_DETAIL:
                raise
            self.skipTest("bindings built without -DHAVE_SSL=ON")

    def tearDown(self):
        self.initiator.stop()
        self.acceptor.stop()

    def _wait_until(self, predicate, timeout=10):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if predicate():
                return True
            time.sleep(0.1)
        return False

    def test_logon_over_ssl(self):
        self.acceptor.start()
        self.initiator.start()

        established = self._wait_until(
            lambda: self.acceptor_app.logged_on and self.initiator_app.logged_on
        )

        self.assertTrue(established, "FIX session over SSL was not established within timeout")
        self.assertEqual(str(self.initiator_app.logged_on[0]), str(self.sender))
        self.assertEqual(str(self.acceptor_app.logged_on[0]), str(self.target))


if __name__ == "__main__":
    unittest.main()
