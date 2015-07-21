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

import gfm.core.queue;

//version = implementedWithSpinlock; // work-around because pthread POSIX function aren't @nogc nothrow :(

version (implementedWithSpinlock)
{
    import dplug.core.spinlock;

    final class UncheckedMutex
    {
    public:
        this() nothrow @nogc
        {
            _lock.initialize();
        }

        ~this() nothrow @nogc
        {
            close();
        }

        void close() nothrow @nogc
        {
           _lock.close();
        }

        void lock() nothrow @nogc
        {
            _lock.lock();
        }

        void unlock() nothrow @nogc
        {
            _lock.unlock();
        }

        bool tryLock() nothrow @nogc
        {
            return _lock.tryLock();
        }

    private:
        Spinlock _lock;
    }
}
else
{

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


/// Queue with inter-thread communication.
/// Support multiple writers, multiple readers.
///
/// Important: Will crash if the queue is overloaded!
///            ie. if the producer produced faster than the consumer consumes.
final class SyncedQueue(T)
{
    private
    {
        FixedSizeQueue!T _queue;
        UncheckedMutex _lock;
    }

    public
    {
        /// Creates a new spin-locked queue with fixed capacity.
        this(size_t capacity)
        {
            _queue = new FixedSizeQueue!T(capacity);
            _lock = new UncheckedMutex();
        }

        ~this()
        {
            close();
        }

        void close()
        {
            _lock.close();
        }

        /// Pushes an item to the back, crash if queue is full!
        /// Thus, never blocks.
        void pushBack(T x) nothrow @nogc
        {
            _lock.lock();
            scope(exit) _lock.unlock();

            _queue.pushBack(x);
        }

        /// Pops an item from the front, block if queue is empty.
        /// Never blocks.
        bool popFront(out T result) nothrow @nogc
        {
            _lock.lock();
            scope(exit) _lock.unlock();

            if (_queue.length() != 0)
            {
                result = _queue.popFront();
                return true;
            }
            else
                return false;
        }
    }
}

unittest
{
    SyncedQueue!int queue;
}