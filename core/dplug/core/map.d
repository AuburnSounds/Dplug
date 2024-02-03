/**
This module implements an associative array.
@nogc associative array, replacement for std::map and std::set.

Difference with Phobos is that the .init are valid and it uses a B-Tree underneath
which makes it faster.

Copyright: Guillaume Piolat 2015-2024.
Copyright: Copyright (C) 2008- by Steven Schveighoffer. Other code
Copyright: 2010- Andrei Alexandrescu. All rights reserved by the respective holders.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
Authors:   Authors: Steven Schveighoffer, $(HTTP erdani.com, Andrei Alexandrescu), Guillaume Piolat
*/
module dplug.core.map;

import std.functional: binaryFun;

import dplug.core.nogc;
import dplug.core.btree;

nothrow:
@nogc:

/// Creates a new empty `Map`.
Map!(K, V, less, allowDuplicates) makeMap(K, V, alias less = "a < b", bool allowDuplicates = false)()
{
    return Map!(K, V, less, allowDuplicates)(42);
}

/// Tree-map, designed to replace std::map usage.
/// The API should looks closely like the builtin associative arrays.
/// O(lg(n)) insertion, removal, and search time.
/// `Map` is designed to operate even without initialization through `makeMap`.
struct Map(K, V, alias less = "a < b", bool allowDuplicates = false)
{
public:
nothrow:
@nogc:

    this(int dummy)
    {
    }

    @disable this(this);

    ~this()
    {
    }

    /// Insert an element in the container, if the container doesn't already contain 
    /// an element with equivalent key. 
    /// Returns: `true` if the insertion took place.
    bool insert(K key, V value)
    {
        return _tree.insert(key, value);
    }

    /// Removes an element from the container.
    /// Returns: `true` if the removal took place.
    bool remove(K key)
    {
        return _tree.remove(key) != 0;
    }

    /// Removes all elements from the map.
    void clearContents()
    {
        destroyNoGC(_tree);
        // _tree reset to .init, still valid
    }

    /// Returns: A pointer to the value corresponding to this key, or null if not available.
    ///          Live builtin associative arrays.
    inout(V)* opBinaryRight(string op)(K key) inout if (op == "in")
    {
        return key in _tree;
    }

    /// Returns: A reference to the value corresponding to this key.
    ///          Null pointer crash if key doesn't exist. 
    ref inout(V) opIndex(K key) inout
    {
        inout(V)* p = key in _tree;
        assert(p !is null);
        return *p;
    }

    /// Updates a value associated with a key, creates it if necessary.
    void opIndexAssign(V value, K key)
    {
        V* p = key in _tree;
        if (p is null)
        {
            insert(key, value); // PERF: this particular call can assume no-dupe
        }
        else
            *p = value;
    }

    /// Returns: `true` if this key is contained.
    bool contains(K key) const
    {
        return _tree.contains(key);
    }

    /// Returns: Number of elements in the map.
    size_t length() const
    {
        return _tree.length;
    }

    /// Returns: `ttue` is the map has no element.
    bool empty() const
    {
        return _tree.empty;
    }

    // Iterate by value only
/*
    /// Fetch a forward range on all values.
    Range!(MapRangeType.value) byValue()
    {
        if (!isInitialized)
            return Range!(MapRangeType.value).init;

        return Range!(MapRangeType.value)(_rbt[]);
    }

    /// ditto
    ConstRange!(MapRangeType.value) byValue() const
    {
        if (!isInitialized)
            return ConstRange!(MapRangeType.value).init;

        return ConstRange!(MapRangeType.value)(_rbt[]);
    }

    /// ditto
    ImmutableRange!(MapRangeType.value) byValue() immutable
    {
        if (!isInitialized)
            return ImmutableRange!(MapRangeType.value).init;
        
        return ImmutableRange!(MapRangeType.value)(_rbt[]);
    }

    // default opSlice is like byValue for builtin associative arrays
    alias opSlice = byValue;

    // Iterate by key only

    /// Fetch a forward range on all keys.
    Range!(MapRangeType.key) byKey()
    {
        if (!isInitialized)
            return Range!(MapRangeType.key).init;

        return Range!(MapRangeType.key)(_rbt[]);
    }

    /// ditto
    ConstRange!(MapRangeType.key) byKey() const
    {
        if (!isInitialized)
            return ConstRange!(MapRangeType.key).init;

        return ConstRange!(MapRangeType.key)(_rbt[]);
    }

    /// ditto
    ImmutableRange!(MapRangeType.key) byKey() immutable
    {
        if (!isInitialized)
            return ImmutableRange!(MapRangeType.key).init;

        return ImmutableRange!(MapRangeType.key)(_rbt[]);
    }

    // Iterate by key-value

    /// Fetch a forward range on all keys.
    Range!(MapRangeType.keyValue) byKeyValue()
    {
        if (!isInitialized)
            return Range!(MapRangeType.keyValue).init;

        return Range!(MapRangeType.keyValue)(_rbt[]);
    }

    /// ditto
    ConstRange!(MapRangeType.keyValue) byKeyValue() const
    {
        if (!isInitialized)
            return ConstRange!(MapRangeType.keyValue).init;

        return ConstRange!(MapRangeType.keyValue)(_rbt[]);
    }

    /// ditto
    ImmutableRange!(MapRangeType.keyValue) byKeyValue() immutable
    {
        if (!isInitialized)
            return ImmutableRange!(MapRangeType.keyValue).init;

        return ImmutableRange!(MapRangeType.keyValue)(_rbt[]);
    }

    // Iterate by single value (return a range where all elements have equal key)

    /// Fetch a forward range on all elements with given key.
    Range!(MapRangeType.value) byGivenKey(K key)
    {
       if (!isInitialized)
            return Range!(MapRangeType.value).init;

        auto kv = KeyValue(key, V.init);
        return Range!(MapRangeType.value)(_rbt.range(kv));
    }

    /// ditto
    ConstRange!(MapRangeType.value) byGivenKey(K key) const
    {
        if (!isInitialized)
            return ConstRange!(MapRangeType.value).init;

        auto kv = KeyValue(key, V.init);
        return ConstRange!(MapRangeType.value)(_rbt.range(kv));
    }

    /// ditto
    ImmutableRange!(MapRangeType.value) byGivenKey(K key) immutable
    {
        if (!isInitialized)
            return ImmutableRange!(MapRangeType.value).init;

        auto kv = KeyValue(key, V.init);
        return ImmutableRange!(MapRangeType.value)(_rbt.range(kv));
    }*/


private:

    //alias Range(MapRangeType type) = MapRange!(RBNode!KeyValue*, type);
    //alias ConstRange(MapRangeType type) = MapRange!(const(RBNode!KeyValue)*, type); /// Ditto
    //alias ImmutableRange(MapRangeType type) = MapRange!(immutable(RBNode!KeyValue)*, type); /// Ditto

    alias InternalTree = BTree!(K, V, less, allowDuplicates, false);
    InternalTree _tree;
}

unittest
{
    // It should be possible to use most function of an uninitialized Map
    // All except functions returning a range will work.
    Map!(int, string) m;

    assert(m.length == 0);
    assert(m.empty);
    assert(!m.contains(7));

    /*auto range = m.byKey();
    assert(range.empty);
    foreach(e; range)
    {        
    }*/

    m[1] = "fun";
}

unittest
{
    void test(bool removeKeys) nothrow @nogc
    {
        {
            auto test = makeMap!(int, string);
            int N = 100;
            foreach(i; 0..N)
            {
                int key = (i * 69069) % 65536;
                test.insert(key, "this is a test");
            }
            foreach(i; 0..N)
            {
                int key = (i * 69069) % 65536;
                assert(test.contains(key));
            }
        
            if (removeKeys)
            {
                foreach(i; 0..N)
                {
                    int key = (i * 69069) % 65536;
                    test.remove(key);
                }
            }
            foreach(i; 0..N)
            {
                int key = (i * 69069) % 65536;
                assert(removeKeys ^ test.contains(key)); // either keys are here or removed
            }            
        }
    }
    test(true);
    test(false);
}

unittest
{
    Map!(string, int) aa = makeMap!(string, int);   // Associative array of ints that are
    // indexed by string keys.
    // The KeyType is string.
    aa["hello"] = 3;  // set value associated with key "hello" to 3
    int value = aa["hello"];  // lookup value from a key
    assert(value == 3);    

    int* p;

    p = ("hello" in aa);
    if (p !is null)
    {
        *p = 4;  // update value associated with key
        assert(aa["hello"] == 4);
    }

    aa.remove("hello");
}

/// Creates a new empty `Set`.
Set!(K, less) makeSet(K, alias less = "a < b", bool allowDuplicates = false)()
{
    return Set!(K, less, allowDuplicates)(42);
}


/// Set, designed to replace std::set usage.
/// O(lg(n)) insertion, removal, and search time.
/// `Set` is designed to operate even without initialization through `makeSet`.
struct Set(K, alias less = "a < b", bool allowDuplicates = false)
{
public:
nothrow:
@nogc:

    this(int dummy)
    {
    }

    @disable this(this);

    ~this()
    {
    }

    /// Insert an element in the container. 
    /// If allowDuplicates is false, this can fail and return `false` 
    /// if the already contains an element with equivalent key. 
    /// Returns: `true` if the insertion took place.
    bool insert(K key)
    {
        ubyte whatever = 0;
        return _tree.insert(key, whatever);
    }

    /// Removes an element from the container.
    /// Returns: `true` if the removal took place.
    bool remove(K key)
    {
        return _tree.remove(key) != 0;
    }

    /// Removes all elements from the set.
    void clearContents()
    {
        destroyNoGC(_tree);
        // _tree reset to .init, still valid
    }

    /// Returns: `true` if the element is present.
    bool opBinaryRight(string op)(K key) inout if (op == "in")
    {
        return (key in _tree) !is null;
    }

    /// Returns: `true` if the element is present.
    bool opIndex(K key) const
    {
        return (key in _tree) !is null;
    }

    /// Returns: `true` if the element is present.
    bool contains(K key) const
    {
        return (key in _tree) !is null;
    }

    /// Fetch a range that spans all the elements in the container.
    /*auto opSlice() inout
    {
        return _tree[];
    }*/

    /// Returns: Number of elements in the set.
    size_t length() const
    {
        return _tree.length();
    }

    /// Returns: `ttue` is the set has no element.
    bool empty() const
    {
        return _tree.empty();
    }

private:

    // dummy type
    alias V = ubyte;

    alias InternalTree = BTree!(K, V, less, allowDuplicates, false);
    InternalTree _tree;

}

unittest
{
    // It should be possible to use most function of an uninitialized Set
    // All except functions returning a range will work.
    Set!(string) set;

    assert(set.length == 0);
    assert(set.empty);
    set.clearContents();
    assert(!set.contains("toto"));

    /*
    auto range = set[];
    assert(range.empty);
    foreach(e; range)
    {
    }*/

    // Finally create the internal state
    set.insert("titi");
    assert(set.contains("titi"));
}


unittest
{
    Set!(string) keywords = makeSet!string;

    assert(keywords.insert("public"));
    assert(keywords.insert("private"));
    assert(!keywords.insert("private"));

    assert(keywords.remove("public"));
    assert(!keywords.remove("non-existent"));

    assert(keywords.contains("private"));
    assert(!keywords.contains("public"));
}
