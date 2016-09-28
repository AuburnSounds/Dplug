/**
* Copyright: Copyright Auburn Sounds 2015-2016
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.core.lockedqueue;

import gfm.core.queue;
import gfm.core.memory;

import dplug.core.unchecked_sync;

/**
    Locked queue for inter-thread communication.
    Support multiple writers, multiple readers.
    Blocks threads either when empty or full.
    @nogc once in use.

    See_also: $(LINK2 #Queue, Queue)
 */
final class LockedQueue(T)
{
    public
    {
        /// Creates a locked queue with an initial capacity.
        this(size_t capacity)
        {
            _queue = new FixedSizeQueue!T(capacity);
            _rwMutex = uncheckedMutex();
            _readerSemaphore = uncheckedSemaphore(0);
            _writerSemaphore = uncheckedSemaphore(cast(uint)capacity);
        }

        ~this()
        {
            debug ensureNotInGC("LockedQueue");
            clear();
        }

        /// Returns: Capacity of the locked queue.
        size_t capacity() const nothrow @nogc
        {
            // no lock-required as capacity does not change
            return _queue.capacity;
        }

        /// Push an item to the back, block if queue is full.
        void pushBack(T x) nothrow @nogc
        {
            _writerSemaphore.wait();
            {
                _rwMutex.lock();
                _queue.pushBack(x);
                _rwMutex.unlock();
            }
            _readerSemaphore.notify();
        }

        /// Push an item to the front, block if queue is full.
        void pushFront(T x) nothrow @nogc
        {
            _writerSemaphore.wait();
            {
                _rwMutex.lock();
                _queue.pushFront(x);
                _rwMutex.unlock();
            }
            _readerSemaphore.notify();
        }

        /// Pop an item from the front, block if queue is empty.
        T popFront() nothrow @nogc
        {
            _readerSemaphore.wait();
            _rwMutex.lock();
            T res = _queue.popFront();
            _rwMutex.unlock();
            _writerSemaphore.notify();
            return res;
        }

        /// Pop an item from the back, block if queue is empty.
        T popBack() nothrow @nogc
        {
            _readerSemaphore.wait();
            _rwMutex.lock();
            T res = _queue.popBack();
            _rwMutex.unlock();
            _writerSemaphore.notify();
            return res;
        }

        /// Tries to pop an item from the front immediately.
        /// Returns: true if an item was returned, false if the queue is empty.
        bool tryPopFront(out T result) nothrow @nogc
        {
            if (_readerSemaphore.tryWait())
            {
                _rwMutex.lock();
                result = _queue.popFront();
                _rwMutex.unlock();
                _writerSemaphore.notify();
                return true;
            }
            else
                return false;
        }

        /// Tries to pop an item from the back immediately.
        /// Returns: true if an item was returned, false if the queue is empty.
        bool tryPopBack(out T result) nothrow @nogc
        {
            if (_readerSemaphore.tryWait())
            {
                _rwMutex.lock();
                result = _queue.popBack();
                _rwMutex.unlock();
                _writerSemaphore.notify();
                return true;
            }
            else
                return false;
        }

        /// Removes all locked queue items.
        void clear() nothrow @nogc
        {
            while (_readerSemaphore.tryWait())
            {
                _rwMutex.lock();
                _queue.popBack();
                _rwMutex.unlock();
                _writerSemaphore.notify();
            }
        }
    }

    private
    {
        FixedSizeQueue!T _queue;
        UncheckedMutex _rwMutex;
        UncheckedSemaphore _readerSemaphore, _writerSemaphore;
    }
}


unittest
{
    import std.stdio;
    auto lq = new LockedQueue!int(3);
    scope(exit) lq.destroy();
    lq.clear();
    lq.pushFront(2);
    lq.pushBack(3);
    lq.pushFront(1);

    // should contain [1 2 3] here
    assert(lq.popBack() == 3);
    assert(lq.popFront() == 1);
    int res;
    if (lq.tryPopFront(res))
    {
        assert(res == 2);
    }
}
