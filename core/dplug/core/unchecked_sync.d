/**
 * The mutex module provides a primitive for maintaining mutually exclusive
 * access.
 *
 * Copyright: Copyright Sean Kelly 2005 - 2009.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Sean Kelly
 * Source:    $(DRUNTIMESRC core/sync/_mutex.d)
 */

/*          Copyright Sean Kelly 2005 - 2009.
 * Distributed under the Boost Software License, Version 1.0.
 *    (See accompanying file LICENSE or copy at
 *          http://www.boost.org/LICENSE_1_0.txt)
 */
 /// Modified to make it @nogc
 /// Added a synchronized ring buffer.

/// Created because of pressing needs of nothrow @nogc synchronization
module dplug.core.unchecked_sync;

public import core.time;

import gfm.core;

version( Windows )
{
    private import core.sys.windows.windows;

    extern (Windows) export nothrow @nogc
    {
        void InitializeCriticalSectionAndSpinCount(CRITICAL_SECTION * lpCriticalSection, DWORD dwSpinCount);
    }
}
else version( OSX )
{
    import core.sys.posix.pthread;
    import core.sync.config;
    import core.stdc.errno;
    import core.sys.posix.time;
    import core.sys.osx.mach.semaphore;    
}
else version( Posix )
{
    import core.sys.posix.pthread;
    import core.sync.config;
    import core.stdc.errno;
    import core.sys.posix.pthread;
    import core.sys.posix.semaphore;
}
else
{
    static assert(false, "Platform not supported");
}

final class UncheckedMutex
{
    this() nothrow @nogc
    {
        version( Windows )
        {
            InitializeCriticalSectionAndSpinCount( &m_hndl, 0 ); // No spinning
        }
        else version( Posix )
        {
            assumeNothrowNoGC(
                (pthread_mutex_t* handle)
                {
                    pthread_mutexattr_t attr = void;
                    pthread_mutexattr_init( &attr );
                    pthread_mutexattr_settype( &attr, PTHREAD_MUTEX_RECURSIVE );
                    pthread_mutex_init( handle, &attr );
                })(&m_hndl);
        }
    }

    ~this()
    {
        debug ensureNotInGC("UncheckedMutex");

        version( Windows )
        {
            DeleteCriticalSection( &m_hndl );
        }
        else version( Posix )
        {
            assumeNothrowNoGC(
                (pthread_mutex_t* handle)
                {
                    pthread_mutex_destroy(handle);
                })(&m_hndl);
        }
    }

    /// Lock mutex
    final void lock() nothrow @nogc
    {
        version( Windows )
        {
            EnterCriticalSection( &m_hndl );
        }
        else version( Posix )
        {
            assumeNothrowNoGC(
                (pthread_mutex_t* handle)
                {
                    pthread_mutex_lock(handle);
                })(&m_hndl);
        }
    }

    // undocumented function for internal use
    final void unlock() nothrow @nogc
    {
        version( Windows )
        {
            LeaveCriticalSection( &m_hndl );
        }
        else version( Posix )
        {
            assumeNothrowNoGC(
                (pthread_mutex_t* handle)
                {
                    pthread_mutex_unlock(handle);
                })(&m_hndl);
        }
    }

    bool tryLock()
    {
        version( Windows )
        {
            return TryEnterCriticalSection( &m_hndl ) != 0;
        }
        else version( Posix )
        {
            int result = assumeNothrowNoGC(
                (pthread_mutex_t* handle)
                {
                    return pthread_mutex_trylock(handle);
                })(&m_hndl);
            return result == 0;
        }
    }


private:
    version( Windows )
    {
        CRITICAL_SECTION    m_hndl;
    }
    else version( Posix )
    {
        pthread_mutex_t     m_hndl;
    }

package:
    version( Posix )
    {
        pthread_mutex_t* handleAddr()
        {
            return &m_hndl;
        }
    }
}


class UncheckedSemaphore
{
    this( uint count = 0 )  nothrow @nogc
    {
        version( Windows )
        {
            m_hndl = CreateSemaphoreA( null, count, int.max, null );
            if( m_hndl == m_hndl.init )
                assert(false);
        }
        else version( OSX )
        {
            auto rc = semaphore_create( mach_task_self(), &m_hndl, SYNC_POLICY_FIFO, count );
            if( rc )
                 assert(false);
        }
        else version( Posix )
        {
            int rc = sem_init( &m_hndl, 0, count );
            if( rc )
                assert(false);
        }
    }


    ~this() nothrow
    {
        debug ensureNotInGC("UncheckedSemaphore");

        version( Windows )
        {
            BOOL rc = CloseHandle( m_hndl );
            assert( rc, "Unable to destroy semaphore" );
        }
        else version( OSX )
        {
            auto rc = semaphore_destroy( mach_task_self(), m_hndl );
            assert( !rc, "Unable to destroy semaphore" );
        }
        else version( Posix )
        {
            int rc = sem_destroy( &m_hndl );
            assert( !rc, "Unable to destroy semaphore" );
        }
    }

    void wait() nothrow @nogc
    {
        version( Windows )
        {
            DWORD rc = WaitForSingleObject( m_hndl, INFINITE );
            assert( rc == WAIT_OBJECT_0 );
        }
        else version( OSX )
        {
            while( true )
            {
                auto rc = semaphore_wait( m_hndl );
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
                if( !sem_wait( &m_hndl ) )
                    return;
                if( errno != EINTR )
                    assert(false);
            }
        }
    }

    bool wait( Duration period ) nothrow @nogc
    in
    {
        assert( !period.isNegative );
    }
    body
    {
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
        else version( OSX )
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
                auto rc = semaphore_timedwait( m_hndl, t );
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
            timespec t = void;
            mktspec( t, period );

            while( true )
            {
                if( !sem_timedwait( &m_hndl, &t ) )
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
        else version( OSX )
        {
            auto rc = semaphore_signal( m_hndl );
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
        else version( OSX )
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
    else version( OSX )
    {
        semaphore_t m_hndl;
    }
    else version( Posix )
    {
        sem_t   m_hndl;
    }
}

