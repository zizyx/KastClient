# Copyright (c) 2014 CEF Python, see the Authors file.
# All rights reserved. Licensed under BSD 3-clause license.
# Project website: https://github.com/cztomczak/cefpython

from libcpp cimport bool as cpp_bool
# noinspection PyUnresolvedReferences
cimport cef_types
from cef_types cimport int64
from cef_ptr cimport CefRefPtr

cdef extern from "include/cef_task.h":
    ctypedef int CefThreadId
    ctypedef cef_types.cef_thread_id_t CefThreadId
    
    cdef cpp_bool CefCurrentlyOn(CefThreadId)
    cdef cpp_bool CefPostTask(CefThreadId threadId,
                              CefRefPtr[CefTask] task)
    cdef cpp_bool CefPostDelayedTask(CefThreadId threadId,
                                     CefRefPtr[CefTask] task,
                                     int64 delay_ms)
    
    cdef cppclass CefTask:
        pass

