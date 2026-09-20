%exception
{
  if(!tryPythonException([&]() mutable 
  { 
    $action
    return true;
  fail:
    return false;
  })) 
  {
    SWIG_fail;
  }
}

%typemap(in) std::string& (std::string temp) {
  temp = std::string((char*)PyUnicode_AsUTF8($input));
  $1 = &temp;
}

%typemap(argout) std::string& {
  if( std::string("$1_type") == "std::string &" )
  {
    if( !PyDict_Check(resultobj) )
      resultobj = PyDict_New();
    PyDict_SetItem( resultobj, PyLong_FromLong(PyDict_Size(resultobj)), PyUnicode_FromString($1->c_str()) );
  }
}

%typemap(in) int& (int temp) {
  SWIG_AsVal_int($input, &temp);
  $1 = &temp;
}

%typemap(argout) int& {
  if( std::string("$1_type") == "int &" )
  {
    if( !PyDict_Check(resultobj) )
      resultobj = PyDict_New();
    PyDict_SetItem( resultobj, PyLong_FromLong(PyDict_Size(resultobj)), PyLong_FromLong(*$1) );    
  }
}

%typemap(in) FIX::DataDictionary const *& (FIX::DataDictionary* temp) {
  $1 = new FIX::DataDictionary*[1];
  *$1 = temp;
}

%typemap(free) FIX::DataDictionary const *& {
  delete[] temp;
}

%typemap(argout) FIX::DataDictionary const *& {
  void* argp;
  FIX::DataDictionary* pDD = 0;
  int res = SWIG_ConvertPtr($input, &argp, SWIGTYPE_p_FIX__DataDictionary, 0 );
  pDD = reinterpret_cast<FIX::DataDictionary *>(argp);
  *pDD = *(*$1);
}

%extend FIX::UtcTimeStamp {
  PyObject *getDateTime() {
      int y, m, d, h, mi, s, fs;
      $self->getYMD(y, m, d);
      $self->getHMS(h, mi, s, fs, 6);
      return PyDateTime_FromDateAndTime(y, m, d, h, mi, s, fs);
  }
}

%rename(FIXException) FIX::Exception;

/* SWIG wraps every C++ call -- destructors included -- in
 *   SWIG_PYTHON_THREAD_BEGIN_ALLOW ... SWIG_PYTHON_THREAD_END_ALLOW
 * i.e. PyEval_SaveThread()/PyEval_RestoreThread(), because a long C++ call must
 * not hold the GIL. That is right everywhere except during interpreter
 * finalization: SwigPyObject_dealloc routes every SWIG-owned object through the
 * generated _wrap_delete_*, so an object still alive at shutdown does the GIL
 * dance on a runtime that is tearing down. CPython tolerated that through 3.14
 * (free-threaded 3.14t included) and made it fatal in 3.15:
 *   Fatal Python error: PyMutex_Unlock: unlocking mutex that is not locked
 *
 * The macros are defined in SWIG's runtime section, and this header block is
 * emitted after it, so redefining them here applies to every wrapper function.
 * When the interpreter is finalizing we simply keep the GIL: the destructors
 * that matter at that point are plain memory operations. A transport still
 * *running* at shutdown is the one case this could block instead of crash --
 * stop() it before exit; see TODO.md.
 */
%header %{
#if defined(SWIG_PYTHON_THREAD_BEGIN_ALLOW)
#undef SWIG_PYTHON_THREAD_BEGIN_ALLOW
#undef SWIG_PYTHON_THREAD_END_ALLOW

#if PY_VERSION_HEX >= 0x030D0000
#define QUICKFIX_PYTHON_IS_FINALIZING() Py_IsFinalizing()
#else
#define QUICKFIX_PYTHON_IS_FINALIZING() _Py_IsFinalizing()
#endif

class Quickfix_Python_Thread_Allow {
  bool status;
  PyThreadState *save;
public:
  void end() { if (status) { status = false; PyEval_RestoreThread(save); } }
  Quickfix_Python_Thread_Allow()
    : status(!QUICKFIX_PYTHON_IS_FINALIZING()),
      save(status ? PyEval_SaveThread() : NULL) {}
  ~Quickfix_Python_Thread_Allow() { end(); }
};

#define SWIG_PYTHON_THREAD_BEGIN_ALLOW Quickfix_Python_Thread_Allow _swig_thread_allow
#define SWIG_PYTHON_THREAD_END_ALLOW   _swig_thread_allow.end()
#endif
%}

%include ../quickfix.i

%pythoncode %{
try:
  import thread
except ImportError:
  import _thread as thread

def _quickfix_start_thread(i_or_a):
  i_or_a.block()
%}

%feature("shadow") FIX::Initiator::start() %{
def start(self):
  thread.start_new_thread(_quickfix_start_thread, (self,))
%}

%feature("shadow") FIX::Acceptor::start() %{
def start(self):
  thread.start_new_thread(_quickfix_start_thread, (self,))
%}

%feature("director:except") FIX::Log::clear {
  if( $error != NULL ) {
    PyObject *ptype, *pvalue, *ptraceback;
    PyErr_Fetch( &ptype, &pvalue, &ptraceback );
    PyErr_Restore( ptype, pvalue, ptraceback );
    PyErr_Print();
    Py_Exit(1);
  }
}
%feature("director:except") FIX::Log::backup {
  if( $error != NULL ) {
    PyObject *ptype, *pvalue, *ptraceback;
    PyErr_Fetch( &ptype, &pvalue, &ptraceback );
    PyErr_Restore( ptype, pvalue, ptraceback );
    PyErr_Print();
    Py_Exit(1);
  }
}
%feature("director:except") FIX::Log::onIncoming {
  if( $error != NULL ) {
    PyObject *ptype, *pvalue, *ptraceback;
    PyErr_Fetch( &ptype, &pvalue, &ptraceback );
    PyErr_Restore( ptype, pvalue, ptraceback );
    PyErr_Print();
    Py_Exit(1);
  }
}
%feature("director:except") FIX::Log::onOutgoing {
  if( $error != NULL ) {
    PyObject *ptype, *pvalue, *ptraceback;
    PyErr_Fetch( &ptype, &pvalue, &ptraceback );
    PyErr_Restore( ptype, pvalue, ptraceback );
    PyErr_Print();
    Py_Exit(1);
  }
}
%feature("director:except") FIX::Log::onEvent {
  if( $error != NULL ) {
    PyObject *ptype, *pvalue, *ptraceback;
    PyErr_Fetch( &ptype, &pvalue, &ptraceback );
    PyErr_Restore( ptype, pvalue, ptraceback );
    PyErr_Print();
    Py_Exit(1);
  }
}

%feature("director:except") FIX::LogFactory::create {
  if( $error != NULL ) {
    PyObject *ptype, *pvalue, *ptraceback;
    PyErr_Fetch( &ptype, &pvalue, &ptraceback );
    PyErr_Restore( ptype, pvalue, ptraceback );
    PyErr_Print();
    Py_Exit(1);
  }
}
%feature("director:except") FIX::LogFactory::destroy {
  if( $error != NULL ) {
    PyObject *ptype, *pvalue, *ptraceback;
    PyErr_Fetch( &ptype, &pvalue, &ptraceback );
    PyErr_Restore( ptype, pvalue, ptraceback );
    PyErr_Print();
    Py_Exit(1);
  }
}



%feature("director:except") FIX::Application::onCreate {
  if( $error != NULL ) {
    PyObject *ptype, *pvalue, *ptraceback;
    PyErr_Fetch( &ptype, &pvalue, &ptraceback );
    PyErr_Restore( ptype, pvalue, ptraceback );
    PyErr_Print();
    Py_Exit(1);
  }
}

%feature("director:except") FIX::Application::onLogon {
  if( $error != NULL ) {
    PyObject *ptype, *pvalue, *ptraceback;
    PyErr_Fetch( &ptype, &pvalue, &ptraceback );
    PyErr_Restore( ptype, pvalue, ptraceback );
    PyErr_Print();
    Py_Exit(1);
  }
}

%feature("director:except") FIX::Application::onLogout {
  if( $error != NULL ) {
    PyObject *ptype, *pvalue, *ptraceback;
    PyErr_Fetch( &ptype, &pvalue, &ptraceback );
    PyErr_Restore( ptype, pvalue, ptraceback );
    PyErr_Print();
    Py_Exit(1);
  }
}

%feature("director:except") FIX::Application::toAdmin {
  if( $error != NULL ) {
    PyObject *ptype, *pvalue, *ptraceback;
    PyErr_Fetch( &ptype, &pvalue, &ptraceback );
    PyErr_Restore( ptype, pvalue, ptraceback );
    PyErr_Print();
    Py_Exit(1);
  }
}

%feature("director:except") FIX::Application::toApp {
  if( $error != NULL ) {
    PyObject *ptype, *pvalue, *ptraceback;
    PyErr_Fetch( &ptype, &pvalue, &ptraceback );
    void *result;

    if( SWIG_ConvertPtr(pvalue, &result, SWIGTYPE_p_FIX__DoNotSend, 0 ) != -1 ) {
      throw *((FIX::DoNotSend*)result);
    } else {
      PyErr_Restore( ptype, pvalue, ptraceback );
      PyErr_Print();
      Py_Exit(1);
    }
  }
}

%feature("director:except") FIX::Application::fromAdmin {
  if( $error != NULL ) {
    PyObject *ptype, *pvalue, *ptraceback;
    PyErr_Fetch( &ptype, &pvalue, &ptraceback );
    void *result;

    if( SWIG_ConvertPtr(pvalue, &result, SWIGTYPE_p_FIX__FieldNotFound, 0 ) != -1 ) {
      throw *((FIX::FieldNotFound*)result);
    } else if( SWIG_ConvertPtr(pvalue, &result, SWIGTYPE_p_FIX__IncorrectDataFormat, 0 ) != -1 ) {
      throw *((FIX::IncorrectDataFormat*)result);
    } else if( SWIG_ConvertPtr(pvalue, &result, SWIGTYPE_p_FIX__IncorrectTagValue, 0 ) != -1 ) {
      throw *((FIX::IncorrectTagValue*)result);
    } else if( SWIG_ConvertPtr(pvalue, &result, SWIGTYPE_p_FIX__RejectLogon, 0 ) != -1 ) {
      throw *((FIX::RejectLogon*)result);
    } else {
      PyErr_Restore( ptype, pvalue, ptraceback );
      PyErr_Print();
      Py_Exit(1);
    }
  }
}

%feature("director:except") FIX::Application::fromApp {
  if( $error != NULL ) {
    PyObject *ptype, *pvalue, *ptraceback;
    PyErr_Fetch( &ptype, &pvalue, &ptraceback );
    void *result;

    if( SWIG_ConvertPtr(pvalue, &result, SWIGTYPE_p_FIX__FieldNotFound, 0 ) != -1 ) {
      throw *((FIX::FieldNotFound*)result);
    } else if( SWIG_ConvertPtr(pvalue, &result, SWIGTYPE_p_FIX__IncorrectDataFormat, 0 ) != -1 ) {
      throw *((FIX::IncorrectDataFormat*)result);
    } else if( SWIG_ConvertPtr(pvalue, &result, SWIGTYPE_p_FIX__IncorrectTagValue, 0 ) != -1 ) {
      throw *((FIX::IncorrectTagValue*)result);
    } else if( SWIG_ConvertPtr(pvalue, &result, SWIGTYPE_p_FIX__UnsupportedMessageType, 0 ) != -1 ) {
      throw *((FIX::UnsupportedMessageType*)result);
    } else {
      PyErr_Restore( ptype, pvalue, ptraceback );
      PyErr_Print();
      Py_Exit(1);
    }
  }
}

%pythoncode %{
class SocketInitiator(SocketInitiatorBase):
  application = 0
  storeFactory = 0
  setting = 0
  logFactory = 0

  def __init__(self, application, storeFactory, settings, logFactory=None):
    if logFactory == None:
      SocketInitiatorBase.__init__(self, application, storeFactory, settings)
    else:
      SocketInitiatorBase.__init__(self, application, storeFactory, settings, logFactory)

    self.application = application
    self.storeFactory = storeFactory
    self.settings = settings
    self.logFactory = logFactory

class SocketAcceptor(SocketAcceptorBase):
  application = 0
  storeFactory = 0
  setting = 0
  logFactory = 0

  def __init__(self, application, storeFactory, settings, logFactory=None):
    if logFactory == None:
      SocketAcceptorBase.__init__(self, application, storeFactory, settings)
    else:
      SocketAcceptorBase.__init__(self, application, storeFactory, settings, logFactory)

    self.application = application
    self.storeFactory = storeFactory
    self.settings = settings
    self.logFactory = logFactory

class ThreadedSocketInitiator(ThreadedSocketInitiatorBase):
  application = 0
  storeFactory = 0
  setting = 0
  logFactory = 0

  def __init__(self, application, storeFactory, settings, logFactory=None):
    if logFactory == None:
      ThreadedSocketInitiatorBase.__init__(self, application, storeFactory, settings)
    else:
      ThreadedSocketInitiatorBase.__init__(self, application, storeFactory, settings, logFactory)

    self.application = application
    self.storeFactory = storeFactory
    self.settings = settings
    self.logFactory = logFactory

class ThreadedSocketAcceptor(ThreadedSocketAcceptorBase):
  application = 0
  storeFactory = 0
  setting = 0
  logFactory = 0

  def __init__(self, application, storeFactory, settings, logFactory=None):
    if logFactory == None:
      ThreadedSocketAcceptorBase.__init__(self, application, storeFactory, settings)
    else:
      ThreadedSocketAcceptorBase.__init__(self, application, storeFactory, settings, logFactory)

    self.application = application
    self.storeFactory = storeFactory
    self.settings = settings
    self.logFactory = logFactory

#if (HAVE_SSL > 0)
class SSLSocketInitiator(SSLSocketInitiatorBase):
  application = 0
  storeFactory = 0
  setting = 0
  logFactory = 0

  def __init__(self, application, storeFactory, settings, logFactory=None):
    if logFactory == None:
      SSLSocketInitiatorBase.__init__(self, application, storeFactory, settings)
    else:
      SSLSocketInitiatorBase.__init__(self, application, storeFactory, settings, logFactory)

    self.application = application
    self.storeFactory = storeFactory
    self.settings = settings
    self.logFactory = logFactory

class SSLSocketAcceptor(SSLSocketAcceptorBase):
  application = 0
  storeFactory = 0
  setting = 0
  logFactory = 0

  def __init__(self, application, storeFactory, settings, logFactory=None):
    if logFactory == None:
      SSLSocketAcceptorBase.__init__(self, application, storeFactory, settings)
    else:
      SSLSocketAcceptorBase.__init__(self, application, storeFactory, settings, logFactory)

    self.application = application
    self.storeFactory = storeFactory
    self.settings = settings
    self.logFactory = logFactory

class ThreadedSSLSocketInitiator(ThreadedSSLSocketInitiatorBase):
  application = 0
  storeFactory = 0
  setting = 0
  logFactory = 0

  def __init__(self, application, storeFactory, settings, logFactory=None):
    if logFactory == None:
      ThreadedSSLSocketInitiatorBase.__init__(self, application, storeFactory, settings)
    else:
      ThreadedSSLSocketInitiatorBase.__init__(self, application, storeFactory, settings, logFactory)

    self.application = application
    self.storeFactory = storeFactory
    self.settings = settings
    self.logFactory = logFactory

class ThreadedSSLSocketAcceptor(ThreadedSSLSocketAcceptorBase):
  application = 0
  storeFactory = 0
  setting = 0
  logFactory = 0

  def __init__(self, application, storeFactory, settings, logFactory=None):
    if logFactory == None:
      ThreadedSSLSocketAcceptorBase.__init__(self, application, storeFactory, settings)
    else:
      ThreadedSSLSocketAcceptorBase.__init__(self, application, storeFactory, settings, logFactory)

    self.application = application
    self.storeFactory = storeFactory
    self.settings = settings
    self.logFactory = logFactory
#endif
%}

%init %{
#ifndef _MSC_VER
      struct sigaction new_action, old_action;
      new_action.sa_handler = SIG_DFL;
      sigemptyset( &new_action.sa_mask );
      new_action.sa_flags = 0;
      sigaction( SIGINT, &new_action, &old_action );
#endif
%}

