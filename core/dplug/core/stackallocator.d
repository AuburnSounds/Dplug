/**
Stack allocator for temporary allocations.

Copyright: Auburn Sounds 2019.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
// TODO deprecated("Will be removed in Dplug v15") for the module itself
module dplug.core.stackallocator;

import core.stdc.stdlib: malloc, free;
import dplug.core.vec;

deprecated("Will be removed in Dplug v14") struct StackAllocator
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
