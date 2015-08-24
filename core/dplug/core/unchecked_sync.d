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

import gfm.core;

version( Windows )
{
    private import core.sys.windows.windows;
}
else version( Posix )
{
    private import core.sys.posix.pthread;
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
            InitializeCriticalSection( &m_hndl );
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
        m_initialized = true;
    }

    ~this() nothrow @nogc
    {
    }

    void close() nothrow @nogc
    {
        if (m_initialized)
        {
            m_initialized = false;
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

    bool                    m_initialized;


package:
    version( Posix )
    {
        pthread_mutex_t* handleAddr()
        {
            return &m_hndl;
        }
    }
}
