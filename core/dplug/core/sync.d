/**
Mutexes, semaphores and condition variables.

Copyright: Sean Kelly 2005 - 2009.
Copyright: Guillaume Piolat 2016 - 2018.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
// This contains part of druntime's core.sys.mutex, core.sys.semaphore core.sys.condition and
// Modified to make it @nogc nothrow
module dplug.core.sync;

import core.time;
import core.atomic;

import dplug.core.vec;
import dplug.core.nogc;

import core.stdc.stdio;
import core.stdc.stdlib: malloc, free;

// emulate conditions variable on Windows
// (this was originally in Phobos for XP compatibility)
version = emulateCondVarWin32;

version (OSX)
    version = Darwin;
else version (iOS)
    version = Darwin;
else version (TVOS)
    version = Darwin;
else version (WatchOS)
    version = Darwin;

version( Windows )
{
    import core.sys.windows.windows;

    extern (Windows) nothrow @nogc
    {
        void InitializeCriticalSectionAndSpinCount(CRITICAL_SECTION * lpCriticalSection, DWORD dwSpinCount);
    }
}
else version( Darwin )
{
    import core.sys.posix.pthread;
    import core.sync.config;
    import core.stdc.errno;
    import core.sys.posix.time;
    static if (__VERSION__ < 2084)
        import core.sys.osx.mach.semaphore; // was removed with DMDFE 2.084
    else 
        import core.sys.darwin.mach.semaphore;
}
else version( Posix )
{
    import core.sync.config;
    import core.stdc.errno;
    import core.sys.posix.pthread;
    import core.sys.posix.semaphore;
    import core.sys.posix.time;
}
else
{
    static assert(false, "Platform not supported");
}


//
// MUTEX
//

/// Returns: A newly created `UnchekedMutex`.
UncheckedMutex makeMutex() nothrow @nogc
{
    return UncheckedMutex(42);
}

private enum PosixMutexAlignment = 64; // Wild guess, no measurements done

// Cargo-culting the spin-count in WTF::Lock
// See: https://webkit.org/blog/6161/locking-in-webkit/
private enum CriticalSectionSpinCount = 40;

struct UncheckedMutex
{
nothrow @nogc:

    private this(int dummyArg)
    {
        assert(!_created);
        lazyThreadSafeInitialization();
    }

    ~this()
    {
        // RACE CONDITION HERE
        // TODO: not easy to make the mutex destruction thread-safe, because one of the
        // thread must wait. Ignore that for now.

        void* mutexHandle = atomicLoad(_mutex); // Can be the mutex handle, or null.

        if (mutexHandle !is null)
        {
            // Now, the mutex could have been destroyed by another thread already.
            // Make a cas to ensure we are first to attempt it.

            if (cas(&_mutex, &mutexHandle, null))
            {
                destroyMutex(mutexHandle);
            }
        }

        _created = 0;
    }

    @disable this(this);

    /// Lock mutex, and create it in a thread-safe way if it doens't exist yet.
    /// This is useful when globals access must be protected by a mutex.
    void lockLazy() @trusted
    {
        lazyThreadSafeInitialization();
        lock();
    }

    /// Lock mutex
    void lock()
    {
        // No sync needed, else would have used lockLazy()
        version( Windows )
        {
            EnterCriticalSection( cast(CRITICAL_SECTION*) _mutex ); 
        }
        else version( Posix )
        {
            assumeNothrowNoGC(
                (pthread_mutex_t* handle)
                {
                    int res = pthread_mutex_lock(handle);
                    if (res != 0)
                        assert(false);
                })(handleAddr());
        }
    }

    // undocumented function for internal use
    void unlock()
    {
        version( Windows )
        {
            LeaveCriticalSection( cast(CRITICAL_SECTION*) _mutex );
        }
        else version( Posix )
        {
            assumeNothrowNoGC(
                (pthread_mutex_t* handle)
                {
                    int res = pthread_mutex_unlock(handle);
                    if (res != 0)
                        assert(false);
                })(handleAddr());
        }
    }

    bool tryLock()
    {
        version( Windows )
        {
            return TryEnterCriticalSection( cast(CRITICAL_SECTION*) _mutex ) != 0;
        }
        else version( Posix )
        {
            int result = assumeNothrowNoGC(
                (pthread_mutex_t* handle)
                {
                    return pthread_mutex_trylock(handle);
                })(handleAddr());
            return result == 0;
        }
    }

    // For debugging purpose
    deprecated void dumpState()
    {
    }


private:
    // on Windows, this is a CRITICAL_SECTION*.
    // else, this is a pthread_mutex_t*
    void* _mutex;

    // Work-around for Issue 16636
    // https://issues.dlang.org/show_bug.cgi?id=16636
    // Still crash with LDC somehow
    long _created = 0;

    static void* createMutex()
    {
        version( Windows )
        {
            CRITICAL_SECTION* critSec = cast(CRITICAL_SECTION*) malloc(CRITICAL_SECTION.sizeof);
            InitializeCriticalSectionAndSpinCount( critSec, CriticalSectionSpinCount );
            return critSec;
        }
        else version( Posix )
        {
            pthread_mutex_t* pmtx = cast(pthread_mutex_t*)( alignedMalloc(pthread_mutex_t.sizeof, PosixMutexAlignment) );

            assumeNothrowNoGC(
                (pthread_mutex_t* handle)
                {
                    pthread_mutexattr_t attr = void;
                    pthread_mutexattr_init( &attr );
                    pthread_mutexattr_settype( &attr, PTHREAD_MUTEX_RECURSIVE );

                    version (Darwin)
                    {
                        // Note: disabled since this breaks thread pool.
                        /+
                            // OSX mutexes are fair by default, but this has a cost for contended locks
                            // Disable fairness.
                            // https://blog.mozilla.org/nfroyd/2017/03/29/on-mutex-performance-part-1/
                            enum _PTHREAD_MUTEX_POLICY_FIRSTFIT = 2;
                            pthread_mutexattr_setpolicy_np(& attr, _PTHREAD_MUTEX_POLICY_FIRSTFIT);
                        +/
                    }

                    pthread_mutex_init( handle, &attr );

                })(pmtx);
                return pmtx;
        }
        else
            static assert(false);
    }

    static void destroyMutex(void* mutex)
    {
        if (mutex is null)
            return;

        // TODO: this should be thread-safe, for example a cas with local variable name or _created

        version( Windows )
        {
            DeleteCriticalSection( cast(CRITICAL_SECTION*) mutex );
            free(mutex);
        }
        else version( Posix )
        {
            assumeNothrowNoGC(
                (pthread_mutex_t* handle)
                {
                    pthread_mutex_destroy(handle);
                })( cast(pthread_mutex_t*) mutex );
            alignedFree(mutex, PosixMutexAlignment);
        }
        else
            static assert(false);
    }

    void lazyThreadSafeInitialization() @trusted
    {
        // Is there an existing mutex already?
        if (atomicLoad(_mutex) !is null)
            return;

        // Create one mutex.
        void* mtx = createMutex();
        void* p = cast(void*)mtx;
        void** here = &_mutex;
        void* ifThis = null;

        // Try to set _mutex.
        if (!cas(here, &ifThis, p))
        {
            // Another thread created _mutex first. Destroy our useless instance.
            destroyMutex(mtx);
        }
    }

package:
    version( Posix )
    {
        pthread_mutex_t* handleAddr() nothrow @nogc
        {
            return cast(pthread_mutex_t*) _mutex;
        }
    }
}

unittest
{
    UncheckedMutex mutex = makeMutex();
    foreach(i; 0..100)
    {
        mutex.lock();
        mutex.unlock();

        if (mutex.tryLock)
            mutex.unlock();
    }
    mutex.destroy();
}

unittest
{
    __gshared UncheckedMutex mutex2;
    mutex2.lockLazy();
    mutex2.unlock();
}



//
// SEMAPHORE
//

/// Returns: A newly created `UncheckedSemaphore`
UncheckedSemaphore makeSemaphore(uint count) nothrow @nogc
{
    return UncheckedSemaphore(count);
}

struct UncheckedSemaphore
{
    private this( uint count ) nothrow @nogc
    {
        version( Windows )
        {
            m_hndl = CreateSemaphoreA( null, count, int.max, null );
            if( m_hndl == m_hndl.init )
                assert(false);
        }
        else version( Darwin )
        {
            mach_port_t task = assumeNothrowNoGC(
                ()
                {
                    return mach_task_self();
                })();

            kern_return_t rc = assumeNothrowNoGC(
                (mach_port_t t, semaphore_t* handle, uint count)
                {
                    return semaphore_create(t, handle, SYNC_POLICY_FIFO, count );
                })(task, &m_hndl, count);

            if( rc )
                 assert(false);
        }
        else version( Posix )
        {
            int rc = sem_init( &m_hndl, 0, count );
            if( rc )
                assert(false);
        }
        _created = 1;
    }

    ~this() nothrow @nogc
    {
        if (_created)
        {
            version( Windows )
            {
                BOOL rc = CloseHandle( m_hndl );
                assert( rc, "Unable to destroy semaphore" );
            }
            else version( Darwin )
            {
                mach_port_t task = assumeNothrowNoGC(
                    ()
                    {
                        return mach_task_self();
                    })();

                kern_return_t rc = assumeNothrowNoGC(
                    (mach_port_t t, semaphore_t handle)
                    {
                        return semaphore_destroy( t, handle );
                    })(task, m_hndl);

                assert( !rc, "Unable to destroy semaphore" );
            }
            else version( Posix )
            {
                int rc = sem_destroy( &m_hndl );
                assert( !rc, "Unable to destroy semaphore" );
            }
            _created = 0;
        }
    }

    @disable this(this);

    void wait() nothrow @nogc
    {
        version( Windows )
        {
            DWORD rc = WaitForSingleObject( m_hndl, INFINITE );
            assert( rc == WAIT_OBJECT_0 );
        }
        else version( Darwin )
        {
            while( true )
            {
                auto rc = assumeNothrowNoGC(
                    (semaphore_t handle)
                    {
                        return semaphore_wait(handle);
                    })(m_hndl);
                if( !rc )
                    return;
                if( rc == KERN_ABORTED && errno == EINTR )
                    continue;
                assert(false);
            }
        }
        else version( Posix )
        {
            while( true )
            {
                if (!assumeNothrowNoGC(
                    (sem_t* handle)
                    {
                        return sem_wait(handle);
                    })(&m_hndl))
                    return;
                if( errno != EINTR )
                    assert(false);
            }
        }
    }

    bool wait( Duration period ) nothrow @nogc
    {
        assert( !period.isNegative );

        version( Windows )
        {
            auto maxWaitMillis = dur!("msecs")( uint.max - 1 );

            while( period > maxWaitMillis )
            {
                auto rc = WaitForSingleObject( m_hndl, cast(uint)
                                               maxWaitMillis.total!"msecs" );
                switch( rc )
                {
                    case WAIT_OBJECT_0:
                        return true;
                    case WAIT_TIMEOUT:
                        period -= maxWaitMillis;
                        continue;
                    default:
                         assert(false);
                }
            }
            switch( WaitForSingleObject( m_hndl, cast(uint) period.total!"msecs" ) )
            {
                case WAIT_OBJECT_0:
                    return true;
                case WAIT_TIMEOUT:
                    return false;
                default:
                    assert(false);
            }
        }
        else version( Darwin )
        {
            mach_timespec_t t = void;
            (cast(byte*) &t)[0 .. t.sizeof] = 0;

            if( period.total!"seconds" > t.tv_sec.max )
            {
                t.tv_sec  = t.tv_sec.max;
                t.tv_nsec = cast(typeof(t.tv_nsec)) period.split!("seconds", "nsecs")().nsecs;
            }
            else
                period.split!("seconds", "nsecs")(t.tv_sec, t.tv_nsec);
            while( true )
            {
                auto rc = assumeNothrowNoGC(
                            (semaphore_t handle, mach_timespec_t t)
                            {
                                return semaphore_timedwait(handle, t);
                            })(m_hndl, t);
                if( !rc )
                    return true;
                if( rc == KERN_OPERATION_TIMED_OUT )
                    return false;
                if( rc != KERN_ABORTED || errno != EINTR )
                     assert(false);
            }
        }
        else version( Posix )
        {
            timespec t;

            assumeNothrowNoGC(
                (ref timespec t, Duration period)
                {
                    mktspec( t, period );
                })(t, period);

            while( true )
            {
                if (! ((sem_t* handle, timespec* t)
                       {
                            return sem_timedwait(handle, t);
                       })(&m_hndl, &t))
                    return true;
                if( errno == ETIMEDOUT )
                    return false;
                if( errno != EINTR )
                    assert(false);
            }
        }
    }

    void notify()  nothrow @nogc
    {
        version( Windows )
        {
            if( !ReleaseSemaphore( m_hndl, 1, null ) )
                assert(false);
        }
        else version( Darwin )
        {
           auto rc = assumeNothrowNoGC(
                        (semaphore_t handle)
                        {
                            return semaphore_signal(handle);
                        })(m_hndl);
            if( rc )
                assert(false);
        }
        else version( Posix )
        {
            int rc = sem_post( &m_hndl );
            if( rc )
                assert(false);
        }
    }

    bool tryWait() nothrow @nogc
    {
        version( Windows )
        {
            switch( WaitForSingleObject( m_hndl, 0 ) )
            {
                case WAIT_OBJECT_0:
                    return true;
                case WAIT_TIMEOUT:
                    return false;
                default:
                    assert(false);
            }
        }
        else version( Darwin )
        {
            return wait( dur!"hnsecs"(0) );
        }
        else version( Posix )
        {
            while( true )
            {
                if( !sem_trywait( &m_hndl ) )
                    return true;
                if( errno == EAGAIN )
                    return false;
                if( errno != EINTR )
                    assert(false);
            }
        }
    }


private:
    version( Windows )
    {
        HANDLE  m_hndl;
    }
    else version( Darwin )
    {
        semaphore_t m_hndl;
    }
    else version( Posix )
    {
        sem_t   m_hndl;
    }
    ulong _created = 0;
}


unittest
{
    foreach(j; 0..4)
    {
        UncheckedSemaphore semaphore = makeSemaphore(1);
        foreach(i; 0..100)
        {
            semaphore.wait();
            semaphore.notify();
            if (semaphore.tryWait())
                semaphore.notify();
        }
    }
}



//
// CONDITION VARIABLE
//


ConditionVariable makeConditionVariable() nothrow @nogc
{
    return ConditionVariable(42);
}

/**
* This struct represents a condition variable as conceived by C.A.R. Hoare.  As
* per Mesa type monitors however, "signal" has been replaced with "notify" to
* indicate that control is not transferred to the waiter when a notification
* is sent.
*/
struct ConditionVariable
{
public:
nothrow:
@nogc:

    /// Initializes a condition variable.
    this(int dummy)
    {
        version( Windows )
        {
            m_blockLock = CreateSemaphoreA( null, 1, 1, null );
            if( m_blockLock == m_blockLock.init )
                assert(false);
            m_blockQueue = CreateSemaphoreA( null, 0, int.max, null );
            if( m_blockQueue == m_blockQueue.init )
                assert(false);

            m_unblockLock = cast(CRITICAL_SECTION*) malloc(CRITICAL_SECTION.sizeof);
            InitializeCriticalSectionAndSpinCount( m_unblockLock, CriticalSectionSpinCount );
        }
        else version( Posix )
        {
            _handle = cast(pthread_cond_t*)( alignedMalloc(pthread_cond_t.sizeof, PosixMutexAlignment) );

            int rc = pthread_cond_init( handleAddr(), null );
            if( rc )
                assert(false);
        }
    }


    ~this()
    {
        version( Windows )
        {
            CloseHandle( m_blockLock );
            CloseHandle( m_blockQueue );
            if (m_unblockLock !is null)
            {
                DeleteCriticalSection( m_unblockLock );
                free(m_unblockLock);
                m_unblockLock = null;
            }
        }
        else version( Posix )
        {
            if (_handle !is null)
            {
                int rc = pthread_cond_destroy( handleAddr() );
                assert( !rc, "Unable to destroy condition" );
                alignedFree(_handle, PosixMutexAlignment);
                _handle = null;
            }
        }
    }

    /// Wait until notified.
    /// The associated mutex should always be the same for this condition variable.
    void wait(UncheckedMutex* assocMutex)
    {
        version( Windows )
        {
            timedWait( INFINITE, assocMutex );
        }
        else version( Posix )
        {
            int rc = pthread_cond_wait( handleAddr(), assocMutex.handleAddr() );
            if( rc )
                assert(false);
        }
    }

    /// Notifies one waiter.
    void notifyOne()
    {
        version( Windows )
        {
            notifyImpl( false );
        }
        else version( Posix )
        {
            int rc = pthread_cond_signal( handleAddr() );
            if( rc )
                assert(false);
        }
    }


    /// Notifies all waiters.
    void notifyAll()
    {
        version( Windows )
        {
            notifyImpl( true );
        }
        else version( Posix )
        {
            int rc = pthread_cond_broadcast( handleAddr() );
            if( rc )
                assert(false);
        }
    }

    version(Posix)
    {
        pthread_cond_t* handleAddr() nothrow @nogc
        {
            return _handle;
        }
    }


private:
    version( Windows )
    {
        bool timedWait( DWORD timeout, UncheckedMutex* assocMutex )
        {
            int   numSignalsLeft;
            int   numWaitersGone;
            DWORD rc;

            rc = WaitForSingleObject( m_blockLock, INFINITE );
            assert( rc == WAIT_OBJECT_0 );

            m_numWaitersBlocked++;

            rc = ReleaseSemaphore( m_blockLock, 1, null );
            assert( rc );

            assocMutex.unlock();

            rc = WaitForSingleObject( m_blockQueue, timeout );
            assert( rc == WAIT_OBJECT_0 || rc == WAIT_TIMEOUT );
            bool timedOut = (rc == WAIT_TIMEOUT);

            EnterCriticalSection( m_unblockLock );

            if( (numSignalsLeft = m_numWaitersToUnblock) != 0 )
            {
                if ( timedOut )
                {
                    // timeout (or canceled)
                    if( m_numWaitersBlocked != 0 )
                    {
                        m_numWaitersBlocked--;
                        // do not unblock next waiter below (already unblocked)
                        numSignalsLeft = 0;
                    }
                    else
                    {
                        // spurious wakeup pending!!
                        m_numWaitersGone = 1;
                    }
                }
                if( --m_numWaitersToUnblock == 0 )
                {
                    if( m_numWaitersBlocked != 0 )
                    {
                        // open the gate
                        rc = ReleaseSemaphore( m_blockLock, 1, null );
                        assert( rc );
                        // do not open the gate below again
                        numSignalsLeft = 0;
                    }
                    else if( (numWaitersGone = m_numWaitersGone) != 0 )
                    {
                        m_numWaitersGone = 0;
                    }
                }
            }
            else if( ++m_numWaitersGone == int.max / 2 )
            {
                // timeout/canceled or spurious event :-)
                rc = WaitForSingleObject( m_blockLock, INFINITE );
                assert( rc == WAIT_OBJECT_0 );
                // something is going on here - test of timeouts?
                m_numWaitersBlocked -= m_numWaitersGone;
                rc = ReleaseSemaphore( m_blockLock, 1, null );
                assert( rc == WAIT_OBJECT_0 );
                m_numWaitersGone = 0;
            }

            LeaveCriticalSection( m_unblockLock );

            if( numSignalsLeft == 1 )
            {
                // better now than spurious later (same as ResetEvent)
                for( ; numWaitersGone > 0; --numWaitersGone )
                {
                    rc = WaitForSingleObject( m_blockQueue, INFINITE );
                    assert( rc == WAIT_OBJECT_0 );
                }
                // open the gate
                rc = ReleaseSemaphore( m_blockLock, 1, null );
                assert( rc );
            }
            else if( numSignalsLeft != 0 )
            {
                // unblock next waiter
                rc = ReleaseSemaphore( m_blockQueue, 1, null );
                assert( rc );
            }
            assocMutex.lock();
            return !timedOut;
        }


        void notifyImpl( bool all )
        {
            DWORD rc;

            EnterCriticalSection( m_unblockLock );

            if( m_numWaitersToUnblock != 0 )
            {
                if( m_numWaitersBlocked == 0 )
                {
                    LeaveCriticalSection( m_unblockLock );
                    return;
                }
                if( all )
                {
                    m_numWaitersToUnblock += m_numWaitersBlocked;
                    m_numWaitersBlocked = 0;
                }
                else
                {
                    m_numWaitersToUnblock++;
                    m_numWaitersBlocked--;
                }
                LeaveCriticalSection( m_unblockLock );
            }
            else if( m_numWaitersBlocked > m_numWaitersGone )
            {
                rc = WaitForSingleObject( m_blockLock, INFINITE );
                assert( rc == WAIT_OBJECT_0 );
                if( 0 != m_numWaitersGone )
                {
                    m_numWaitersBlocked -= m_numWaitersGone;
                    m_numWaitersGone = 0;
                }
                if( all )
                {
                    m_numWaitersToUnblock = m_numWaitersBlocked;
                    m_numWaitersBlocked = 0;
                }
                else
                {
                    m_numWaitersToUnblock = 1;
                    m_numWaitersBlocked--;
                }
                LeaveCriticalSection( m_unblockLock );
                rc = ReleaseSemaphore( m_blockQueue, 1, null );
                assert( rc );
            }
            else
            {
                LeaveCriticalSection( m_unblockLock );
            }
        }


        // NOTE: This implementation uses Algorithm 8c as described here:
        //       http://groups.google.com/group/comp.programming.threads/
        //              browse_frm/thread/1692bdec8040ba40/e7a5f9d40e86503a
        HANDLE              m_blockLock;    // auto-reset event (now semaphore)
        HANDLE              m_blockQueue;   // auto-reset event (now semaphore)
        CRITICAL_SECTION*   m_unblockLock           = null;  // internal mutex/CS
        int                 m_numWaitersGone        = 0;
        int                 m_numWaitersBlocked     = 0;
        int                 m_numWaitersToUnblock   = 0;
    }
    else version( Posix )
    {
        pthread_cond_t*     _handle;
    }
}

unittest
{
    import dplug.core.thread;

    auto mutex = makeMutex();
    auto condvar = makeConditionVariable();

    bool finished = false;

    // Launch a thread that wait on this condition
    Thread t = launchInAThread(
        () {
            mutex.lock();
            while(!finished)
                condvar.wait(&mutex);
            mutex.unlock();
        });

    // Notify termination
    mutex.lock();
        finished = true;
    mutex.unlock();
    condvar.notifyOne();

    t.join();
}
