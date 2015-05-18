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

/// Created because of pressing needs of nothrow @nogc synchronization
module dplug.plugin.unchecked_sync;

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

final class UncheckedMutex : Object.Monitor
{
    this() nothrow @nogc
    {
        version( Windows )
        {
            InitializeCriticalSection( &m_hndl );
        }
        else version( Posix )
        {
            pthread_mutexattr_t attr = void;
            pthread_mutexattr_init( &attr );
            pthread_mutexattr_settype( &attr, PTHREAD_MUTEX_RECURSIVE );
            pthread_mutex_init( &m_hndl, &attr );
        }
        m_initialized = true;
    }

    ~this() nothrow @nogc
    {
        close();       
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
                pthread_mutex_destroy( &m_hndl );
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
            pthread_mutex_lock( &m_hndl );
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
            pthread_mutex_unlock( &m_hndl );
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
            return pthread_mutex_trylock( &m_hndl ) == 0;
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

final class SyncValue(T)
{
    this() nothrow @nogc
    {
    }

    this(T value) nothrow @nogc
    {
        _value = value;
    }

    ~this() nothrow @nogc
    {
        close();
    }

    void close() nothrow @nogc
    {
        mutex.close();
    }

    void set(T newValue) nothrow @nogc
    {
        _mutex.lock();
        scope(exit) _mutex.unlock();
        _value = newValue;
    }

    T get() nothrow @nogc
    {
        _mutex.lock();
        scope(exit) _mutex.unlock();
        return _value;
    }

private:
    UncheckedMutex mutex;
    T _value = T.init;
}