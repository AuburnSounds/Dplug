/**
 * The thread module provides support for thread creation and management.
 *
 * Copyright: Copyright Sean Kelly 2005 - 2012.
 * Copyright:  Copyright (c) 2009-2011, David Simcha.
 * Copyright: Copyright Auburn Sounds 2016
 * License: Distributed under the
 *      $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0).
 *    (See accompanying file LICENSE)
 * Authors:   Sean Kelly, Walter Bright, Alex Rønne Petersen, Martin Nowak, David Simcha, Guillaume Piolat
 */
module dplug.core.thread;

import dplug.core.nogc;
import dplug.core.lockedqueue;
import dplug.core.sync;

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

version(OSX)
{
    extern(C) nothrow @nogc
    int sysctlbyname(const(char)*, void *, size_t *, void *, size_t);
}


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
    /// Warning: It is STRONGLY ADVISED to pass a class member delegate to have
    ///          the right delegate context.
    ///          Passing struct method delegates are currently UNSUPPORTED.
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

            // verify this
            assert(checkValue0 == 0x11223344);
            assert(checkValue1 == 0x55667788);
        }

        int checkValue0 = 0x11223344;
        int checkValue1 = 0x55667788;
        int innerInt = 0;
        Thread t;
    }

    auto a = new A;
    a.t.join();
    assert(a.innerInt == 2);
    a.destroy();
    assert(outerInt == 1);
}

/// Launch a function in a newly created thread, which is destroyed afterwards.
/// Return the thread so that you can call `.join()` on it.
Thread launchInAThread(ThreadDelegate dg) nothrow @nogc
{
    Thread t = makeThread(dg);
    t.start();
    return t;
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


//
// Thread-pool
//

/// Returns: Number of CPUs.
int getTotalNumberOfCPUs() nothrow @nogc
{
    version(Windows)
    {
        import core.sys.windows.windows : SYSTEM_INFO, GetSystemInfo;
        SYSTEM_INFO si;
        GetSystemInfo(&si);
        int procs = cast(int) si.dwNumberOfProcessors;
        if (procs < 1)
            procs = 1;
        return procs;
    }
    else version(linux)
    {
        import core.sys.posix.unistd : _SC_NPROCESSORS_ONLN, sysconf;
        return cast(int) sysconf(_SC_NPROCESSORS_ONLN);
    }
    else version(OSX)
    {
        auto nameStr = "machdep.cpu.core_count\0".ptr;
        uint ans;
        size_t len = uint.sizeof;
        sysctlbyname(nameStr, &ans, &len, null, 0);
        return cast(int)ans;
    }
    else
        static assert(false, "OS unsupported");
}

alias ThreadPoolDelegate = void delegate(int workItem) nothrow @nogc;


/// Rewrite of the ThreadPool using condition variables.
/// FUTURE: this could be speed-up by using futures. Description of the task
///         and associated condition+mutex would go in an external struct.
/// Note: the interface of the thread-pool itself is not thread-safe, you cannot give orders from
///       multiple threads at once.
class ThreadPool
{
public:
nothrow:
@nogc:

    /// Creates a thread-pool.
    this(int numThreads = 0, size_t stackSize = 0)
    {
        // Create sync first
        _workMutex = makeMutex();
        _workCondition = makeConditionVariable();

        _finishMutex = makeMutex();
        _finishCondition = makeConditionVariable();

        // Create threads
        if (numThreads == 0)
            numThreads = getTotalNumberOfCPUs();
        _threads = mallocSlice!Thread(numThreads);
        foreach(ref thread; _threads)
        {
            thread = makeThread(&workerThreadFunc, stackSize);
            thread.start();
        }
    }

    /// Destroys a thread-pool.
    ~this()
    {
        if (_threads !is null)
        {
            assert(_state == State.initial);

            // Put the threadpool is stop state
            _workMutex.lock();
                _stopFlag = true;
            _workMutex.unlock();

            // Notify all workers
            _workCondition.notifyAll();

            // Wait for each thread termination
            foreach(ref thread; _threads)
                thread.join();

            // Detroys each thread
            foreach(ref thread; _threads)
                thread.destroy();
            freeSlice(_threads);
            _threads = null;
        }
    }

    /// Calls the delegate in parallel, with 0..count as index.
    /// Immediate waiting for completion.
    void parallelFor(int count, scope ThreadPoolDelegate dg)
    {
        assert(_state == State.initial);

        // Do not launch worker threads for one work-item, not worth it.
        // (but it is worth it in async).
        if (count == 1)
        {
            dg(0);
            return;
        }

        // Unleash parallel threads.
        parallelForAsync(count, dg);

        // Wait for completion immediately.
        waitForCompletion(); 
    }

    /// Same, but does not wait for completion. 
    /// You cannot have 2 concurrent parallelFor for the same thread-pool.
    void parallelForAsync(int count, scope ThreadPoolDelegate dg)
    {
        assert(_state == State.initial);

        if (count == 0) // no tasks, exit immediately
            return;

        // At this point we assume all worker threads are waiting for messages

        // Sets the current task
        _workMutex.lock();

        _taskDelegate = dg;       // immutable during this parallelFor
        _taskNumWorkItem = count; // immutable during this parallelFor
        _taskCurrentWorkItem = 0;
        _taskCompleted = 0;

        _workMutex.unlock();

        // wake up all threads
        // FUTURE: if number of tasks < number of threads only wake up the necessary amount of threads
        _workCondition.notifyAll();

        _state = State.parallelForInProgress;
    }

    /// Wait for completion of the previous parallelFor, if any.
    // It's always safe to call this function before doing another parallelFor.
    void waitForCompletion()
    {
        if (_state == State.initial)
            return; // that means that parallel threads were not launched

        assert(_state == State.parallelForInProgress);

        _finishMutex.lock();
        scope(exit) _finishMutex.unlock();

        // FUTURE: order thread will be waken up multiple times
        //         (one for every completed task)
        //         maybe that can be optimized
        while (_taskCompleted < _taskNumWorkItem)
        {
            _finishCondition.wait(&_finishMutex);
        }

        _state = State.initial;
    }

private:
    Thread[] _threads = null;

    // Used to signal more work
    UncheckedMutex _workMutex;
    ConditionVariable _workCondition;

    // Used to signal completion
    UncheckedMutex _finishMutex;
    ConditionVariable _finishCondition;

    // These fields represent the current task group (ie. a parallelFor)
    ThreadPoolDelegate _taskDelegate;
    int _taskNumWorkItem;     // total number of tasks in this task group
    int _taskCurrentWorkItem; // current task still left to do (protected by _workMutex)
    int _taskCompleted;       // every task < taskCompleted has already been completed (protected by _finishMutex)

    bool _stopFlag;

    bool hasWork()
    {
        return _taskCurrentWorkItem < _taskNumWorkItem;
    }

    // Represent the thread-pool state from the user POV
    enum State
    {
        initial,               // tasks can be launched
        parallelForInProgress, // task were launched, but not waited one
    }
    State _state = State.initial;

    // What worker threads do
    // MAYDO: threads come here with bad context with struct delegates
    void workerThreadFunc()
    {
        while (true)
        {
            int workItem = -1;
            {
                _workMutex.lock();
                scope(exit) _workMutex.unlock();

                // Wait for notification
                while (!_stopFlag && !hasWork())
                    _workCondition.wait(&_workMutex);

                if (_stopFlag && !hasWork())
                    return;

                assert(hasWork());

                // Pick a task and increment counter
                workItem = _taskCurrentWorkItem;
                _taskCurrentWorkItem++;
            }

            assert(workItem != -1);

            // Do the actual task
            _taskDelegate(workItem);

            // signal completion of one more task
            {
                _finishMutex.lock();
                _taskCompleted++;
                _finishMutex.unlock();

                _finishCondition.notifyOne(); // wake-up
            }
        }
    }
}


unittest
{
    import core.atomic;
    import dplug.core.nogc;

    struct A
    {
        ThreadPool _pool;

        this(int dummy)
        {
            _pool = mallocEmplace!ThreadPool();
        }

        ~this()
        {
            _pool.destroy();
        }

        void launch(int count, bool async) nothrow @nogc
        {
            if (async)
            {
                _pool.parallelForAsync(count, &loopBody);
                _pool.waitForCompletion();
            }
            else
                _pool.parallelFor(count, &loopBody);
        }

        void loopBody(int workItem) nothrow @nogc
        {
            atomicOp!"+="(counter, 1);
        }

        shared(int) counter = 0;
    }

    auto a = A(4);
    a.launch(10, false);
    assert(a.counter == 10);

    a.launch(500, true);
    assert(a.counter == 510);

    a.launch(1, false);
    assert(a.counter == 511);

    a.launch(1, true);
    assert(a.counter == 512);

    a.launch(0, true);
    assert(a.counter == 512);
    a.launch(0, false);
    assert(a.counter == 512);
}