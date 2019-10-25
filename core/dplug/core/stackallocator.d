/**
Stack allocator for temporary allocations.

Copyright: Auburn Sounds 2019.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.core.stackallocator;

import core.stdc.stdlib: malloc, free;
import dplug.core.vec;

struct StackAllocator
{
private:
    Vec!(ubyte*) bucketArray;
    uint numUsedPages;
    uint currentPageFreeBytes;
    enum PAGE_SIZE = 1024 * 1024 * 1024; // 1MB

    struct State
    {
        uint savedNumUsedPages;
        uint savedCurrentPageFreeBytes;
    }

public:

    @disable this(this); // non copyable

    ~this()
    {
        foreach(ubyte* bucket; bucketArray)
            free(bucket);
    }

    /// Save allocation state
    State saveState()
    {
        return State(numUsedPages, currentPageFreeBytes);
    }

    /// Pop allocation state
    void restoreState(State state)
    {
        numUsedPages = state.savedNumUsedPages;
        currentPageFreeBytes = state.savedCurrentPageFreeBytes;
    }

    /// return pointer to len x T.sizeof bytes of uninitialized memory
    T[] makeArray(T)(size_t len)
    {
        size_t allocSize = len * T.sizeof;
        assert(allocSize <= PAGE_SIZE, "Requested size is bigger that page size");

        if (currentPageFreeBytes < allocSize)
            setupNextPage;

        size_t nextByte = PAGE_SIZE - currentPageFreeBytes;
        currentPageFreeBytes -= allocSize;

        ubyte* pagePtr = bucketArray[numUsedPages-1];
        ubyte[] bytes = pagePtr[nextByte..nextByte+allocSize];

        return cast(T[])bytes;
    }

    private void setupNextPage()
    {
        if (numUsedPages == bucketArray.length)
        {
            ubyte* newBucket = cast(ubyte*)malloc(PAGE_SIZE);
            bucketArray.pushBack(newBucket);
        }
        // alloc from new page
        ++numUsedPages;
        currentPageFreeBytes = PAGE_SIZE;
    }
}

unittest
{
    StackAllocator allocator;
    auto saved = allocator.saveState;
    uint[] arr = allocator.makeArray!uint(10);
    arr[] = 42;
    assert(arr.length == 10);
    allocator.restoreState(saved);

    uint[] arr2 = allocator.makeArray!uint(10);
    arr2[] = 48;

    assert(arr[0] == 48);

    // multiple allocations
    uint[] arr3 = allocator.makeArray!uint(10);
    arr3[] = 60;

    // doesn't overwrite arr2
    assert(arr2[0] == 48);
    assert(arr2[$-1] == 48);

    allocator.restoreState(saved);

    // test new page allocation
    allocator.makeArray!uint(1);
    allocator.makeArray!uint(StackAllocator.PAGE_SIZE / uint.sizeof);

    allocator.restoreState(saved);

    // test page reuse
    allocator.makeArray!uint(StackAllocator.PAGE_SIZE / uint.sizeof);
}