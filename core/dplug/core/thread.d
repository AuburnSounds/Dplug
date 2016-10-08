/**
 * The thread module provides support for thread creation and management.
 *
 * Copyright: Copyright Sean Kelly 2005 - 2012.
 * Copyright: Copyright Auburn Sounds 2016
 * License: Distributed under the
 *      $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0).
 *    (See accompanying file LICENSE)
 * Authors:   Sean Kelly, Walter Bright, Alex Rønne Petersen, Martin Nowak, Guillaume Piolat
 */
module dplug.core.thread;

import dplug.core.nogc;

version(Posix)
    import core.sys.posix.pthread;
else version(Windows)
{
    import core.stdc.stdint : uintptr_t;
    import core.sys.windows.windef;
    import core.sys.windows.winbase;
    import core.thread;

    extern (Windows) alias btex_fptr = uint function(void*) ;
    extern (C) uintptr_t _beginthreadex(void*, uint, btex_fptr, void*, uint, uint*) nothrow @nogc;
}
else
    static assert(false, "Platform not supported");


alias ThreadDelegate = void delegate() nothrow @nogc;



Thread makeThread(ThreadDelegate callback, size_t stackSize = 0) nothrow @nogc
{
    return Thread(callback, stackSize);
}

/// Optimistic thread, failure not supported
struct Thread
{
nothrow:
@nogc:
public:

    /// Create a suspended thread.
    /// Params:
    ///     callback The delegate that will be called by the thread
    ///     stackSize The thread stack size in bytes. 0 for default size.
    this(ThreadDelegate callback, size_t stackSize = 0)
    {
        _stackSize = stackSize;
        _callback = callback;
    }

    /// Destroys a thread. The thread is supposed to be finished at this point.
    ~this()
    {
        if (!_started)
            return;

        version(Posix)
        {
            pthread_detach(_id);
        }
        else version(Windows)
        {
            CloseHandle(_id);
        }
    }

    @disable this(this);

    /// Starts the thread. Threads are created suspended. This function can
    /// only be called once.
    void start()
    {
        assert(!_started);
        version(Posix)
        {
            pthread_attr_t attr;

            int err = assumeNothrowNoGC(
                (pthread_attr_t* pattr)
                {
                    return pthread_attr_init(pattr);
                })(&attr);

            if (err != 0)
                assert(false);

            if(_stackSize != 0)
            {
                int err2 = assumeNothrowNoGC(
                    (pthread_attr_t* pattr, size_t stackSize)
                    {
                        return pthread_attr_setstacksize(pattr, stackSize);
                    })(&attr, _stackSize);
                if (err2 != 0)
                    assert(false);
            }

            int err3 = pthread_create(&_id, &attr, &posixThreadEntryPoint, &_callback);
            if (err3 != 0)
                assert(false);

            int err4 = assumeNothrowNoGC(
                (pthread_attr_t* pattr)
                {
                    return pthread_attr_destroy(pattr);
                })(&attr);
            if (err4 != 0)
                assert(false);
        }

        version(Windows)
        {
            
            uint dummy;
            _id = cast(HANDLE) _beginthreadex(null,
                                              cast(uint)_stackSize,
                                              &windowsThreadEntryPoint,
                                              &_callback,
                                              CREATE_SUSPENDED, 
                                              &dummy);
            if (cast(size_t)_id == 0)
                assert(false);
            if (ResumeThread(_id) == -1)
                assert(false);            
        }
    }

    /// Wait for that thread termination
    void join()
    {
        version(Posix)
        {
            void* returnValue;
            if (0 != pthread_join(_id, &returnValue))
                assert(false);
        }
        else version(Windows)
        {
            if(WaitForSingleObject(_id, INFINITE) != WAIT_OBJECT_0)
                assert(false);
            CloseHandle(_id);
        }
    }

private:
    version(Posix) pthread_t _id;
    version(Windows) HANDLE _id;
    ThreadDelegate _callback;
    size_t _stackSize;
    bool _started = false;
}

version(Posix)
{
    extern(C) void* posixThreadEntryPoint(void* threadContext) nothrow @nogc
    {
        ThreadDelegate dg = *cast(ThreadDelegate*)(threadContext);
        dg(); // hopfully called with the right context pointer
        return null;
    }
}

version(Windows)
{
    extern (Windows) uint windowsThreadEntryPoint(void* threadContext) nothrow @nogc
    {
        ThreadDelegate dg = *cast(ThreadDelegate*)(threadContext);
        dg();
        return 0;
    }
}

unittest
{
    int outerInt = 0;

    class A
    {
    nothrow @nogc:
        this()
        {
            t = makeThread(&f);
            t.start();
        }

        void join()
        {
            t.join();
        }

        void f()
        {            
            outerInt = 1;
            innerInt = 2;
        }

        int innerInt = 0;
        Thread t;
    }

    auto a = new A();
    a.t.join();
    assert(a.innerInt == 2);
    a.destroy();
    assert(outerInt == 1);
}


version(Windows)
{
    /// Returns: current thread identifier.
    void* currentThreadId() nothrow @nogc
    {
        return cast(void*)GetCurrentThreadId();
    }
}
else version(Posix)
{
    /// Returns: current thread identifier.
    void* currentThreadId() nothrow @nogc
    {
        return assumeNothrowNoGC(
                ()
                {
                    return cast(void*)(pthread_self());
                })();
    }
}