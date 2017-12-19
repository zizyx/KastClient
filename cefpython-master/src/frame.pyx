# Copyright (c) 2012 CEF Python, see the Authors file.
# All rights reserved. Licensed under BSD 3-clause license.
# Project website: https://github.com/cztomczak/cefpython

include "cefpython.pyx"
include "browser.pyx"

cdef dict g_pyFrames = {}

cdef object GetUniqueFrameId(int browserId, object frameId):
    return str(browserId) +"#"+ str(frameId)

cdef PyFrame GetPyFrameById(int browserId, object frameId):
    cdef object uniqueFrameId = GetUniqueFrameId(browserId, frameId)
    if uniqueFrameId in g_pyFrames:
        return g_pyFrames[uniqueFrameId]
    return None

cdef PyFrame GetPyFrame(CefRefPtr[CefFrame] cefFrame):
    global g_pyFrames

    if <void*>cefFrame == NULL or not cefFrame.get():
        raise Exception("GetPyFrame(): CefFrame reference is NULL")

    cdef PyFrame pyFrame
    cdef object frameId = cefFrame.get().GetIdentifier()  # int64
    cdef int browserId = cefFrame.get().GetBrowser().get().GetIdentifier()
    assert (frameId and browserId), "frameId or browserId empty"
    cdef object uniqueFrameId = GetUniqueFrameId(browserId, frameId)

    if uniqueFrameId in g_pyFrames:
        return g_pyFrames[uniqueFrameId]

    # This code probably ain't needed.
    # ----
    cdef list toRemove = []
    for uFid, pyFrame in g_pyFrames.items():
        if not pyFrame.cefFrame.get():
            toRemove.append(uFid)
    for uFid in toRemove:
        Debug("GetPyFrame(): removing an empty CefFrame reference, "
              "uniqueFrameId = %s" % uniqueFrameId)
        del g_pyFrames[uFid]
    # ----

    pyFrame = PyFrame(browserId, frameId)
    pyFrame.cefFrame = cefFrame

    if browserId in g_unreferenced_browsers:
        # Browser was already globally unreferenced in OnBeforeClose,
        # thus all frames are globally unreferenced too. Create a new
        # incomplete instance of PyFrame object. Read comments in
        # browser.pyx > GetPyBrowser and in Browser.md for what
        # "incomplete" means.
        pass
    else:
        # Keep a global reference to this frame only if the browser
        # wasn't destroyed in OnBeforeClose. Otherwise we would leave
        # dead frames references living forever.
        # SIDE EFFECT: two calls to GetPyFrame for the same frame object
        #              may return two different PyFrame objects. Compare
        #              frame objects always using GetIdentifier().
        # Debug("GetPyFrame(): create new PyFrame, frameId=%s" % frameId)
        g_pyFrames[uniqueFrameId] = pyFrame
    return pyFrame

cdef void RemovePyFrame(int browserId, object frameId) except *:
    # Called from V8ContextHandler_OnContextReleased().
    global g_pyFrames
    cdef object uniqueFrameId = GetUniqueFrameId(browserId, frameId)
    if uniqueFrameId in g_pyFrames:
        Debug("del g_pyFrames[%s]" % uniqueFrameId)
        del g_pyFrames[uniqueFrameId]
    else:
        Debug("RemovePyFrame() FAILED: uniqueFrameId = %s" % uniqueFrameId)

cdef void RemovePyFramesForBrowser(int browserId) except *:
    # Called from LifespanHandler_BeforeClose().
    cdef list toRemove = []
    cdef object uniqueFrameId
    cdef PyFrame pyFrame
    global g_pyFrames
    for uniqueFrameId, pyFrame in g_pyFrames.iteritems():
        if pyFrame.GetBrowserIdentifier() == browserId:
            toRemove.append(uniqueFrameId)
    for uniqueFrameId in toRemove:
        Debug("del g_pyFrames[%s]" % uniqueFrameId)
        del g_pyFrames[uniqueFrameId]

cdef class PyFrame:
    cdef CefRefPtr[CefFrame] cefFrame
    cdef int browserId
    cdef object frameId

    cdef CefRefPtr[CefFrame] GetCefFrame(self) except *:
        # Do not call IsValid() here, if the frame does not exist
        # then no big deal, no reason to crash the application.
        # The CEF calls will fail, but they also won't cause crash.
        if <void*>self.cefFrame != NULL and self.cefFrame.get():
            return self.cefFrame
        raise Exception("PyFrame.GetCefFrame() failed: CefFrame was destroyed")

    def __init__(self, int browserId, int frameId):
        self.browserId = browserId
        self.frameId = frameId

    cpdef py_bool IsValid(self):
        if <void*>self.cefFrame != NULL and self.cefFrame.get() \
                and self.cefFrame.get().IsValid():
            return True
        return False

    def CallFunction(self, *args):
        # DEPRECATED - keep for backwards compatibility.
        self.ExecuteFunction(*args)

    cpdef py_void Copy(self):
        self.GetCefFrame().get().Copy()

    cpdef py_void Cut(self):
        self.GetCefFrame().get().Cut()

    cpdef py_void Delete(self):
        self.GetCefFrame().get().Delete()

    def ExecuteFunction(self, funcName, *args):
        # No need to enter V8 context as we're calling javascript
        # asynchronously using ExecuteJavascript() function.
        code = funcName+"("
        for i in range(0, len(args)):
            if i != 0:
                code += ", "
            code += json.dumps(args[i])
        code += ")"
        self.ExecuteJavascript(code)

    cpdef py_void ExecuteJavascript(self, py_string jsCode,
            py_string scriptUrl="", int startLine=1):
        self.GetCefFrame().get().ExecuteJavaScript(PyToCefStringValue(jsCode),
                PyToCefStringValue(scriptUrl), startLine)

    cpdef object GetIdentifier(self):
        # It is better to save browser and frame identifiers during
        # browser instantiation. When freeing PyBrowser and PyFrame
        # we need these identifiers. CefFrame and CefBrowser may already
        # be freed and calling methods on these objects may fail, this
        # may or may not include GetIdentifier() method, but let's be sure.
        return self.frameId

    cpdef PyFrame GetParent(self):
        return GetPyFrame(self.GetCefFrame().get().GetParent())

    cpdef PyBrowser GetBrowser(self):
        return GetPyBrowser(self.GetCefFrame().get().GetBrowser())

    cpdef int GetBrowserIdentifier(self) except *:
        return self.browserId

    cpdef str GetName(self):
        return CefToPyString(self.GetCefFrame().get().GetName())

    cpdef py_void GetSource(self, object visitor):
        self.GetCefFrame().get().GetSource(CreateStringVisitor(visitor))

    cpdef py_void GetText(self, object visitor):
        self.GetCefFrame().get().GetText(CreateStringVisitor(visitor))

    cpdef str GetUrl(self):
        return CefToPyString(self.GetCefFrame().get().GetURL())

    cpdef py_bool IsFocused(self):
        return self.GetCefFrame().get().IsFocused()

    cpdef py_bool IsMain(self):
        return self.GetCefFrame().get().IsMain()

    cpdef py_void LoadString(self, py_string value, py_string url):
        cdef CefString cefValue
        cdef CefString cefUrl
        PyToCefString(value, cefValue)
        PyToCefString(url, cefUrl)
        self.GetCefFrame().get().LoadString(cefValue, cefUrl)

    cpdef py_void LoadUrl(self, py_string url):
        url = GetNavigateUrl(url)
        cdef CefString cefUrl
        PyToCefString(url, cefUrl)
        self.GetCefFrame().get().LoadURL(cefUrl)

    cpdef py_void Paste(self):
        self.GetCefFrame().get().Paste()

    cpdef py_void Redo(self):
        self.GetCefFrame().get().Redo()

    cpdef py_void SelectAll(self):
        self.GetCefFrame().get().SelectAll()

    cpdef py_void Undo(self):
        self.GetCefFrame().get().Undo()

    cpdef py_void ViewSource(self):
        self.GetCefFrame().get().ViewSource()
