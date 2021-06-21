/**
This module implements an associative array.
@nogc associative array, replacement for std::map and std::set.
Implementation of Red Black Tree from Phobos.

Copyright: Guillaume Piolat 2015-2016.
Copyright: Copyright (C) 2008- by Steven Schveighoffer. Other code
Copyright: 2010- Andrei Alexandrescu. All rights reserved by the respective holders.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
Authors:   Authors: Steven Schveighoffer, $(HTTP erdani.com, Andrei Alexandrescu), Guillaume Piolat
*/
module dplug.core.map;

import std.functional: binaryFun;

import dplug.core.nogc;

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
        lazyInitialize();
    }

    @disable this(this);

    ~this()
    {
        if (_rbt !is null)
        {
            destroyFree(_rbt);
            _rbt = null;
        }
    }

    /// Insert an element in the container, if the container doesn't already contain 
    /// an element with equivalent key. 
    /// Returns: `true` if the insertion took place.
    bool insert(K key, V value)
    {
        lazyInitialize();

        auto kv = KeyValue(key, value);
        assert(_rbt);
        return _rbt.insert(kv) != 0;
    }

    /// Removes an element from the container.
    /// Returns: `true` if the removal took place.
    bool remove(K key)
    {
        if (!isInitialized)
            return false;

        auto kv = KeyValue(key, V.init);
        return _rbt.removeKey(kv) != 0;
    }

    /// Removes all elements from the map.
    void clearContents()
    {
        if (!isInitialized)
            return;

        while(_rbt.length > 0)
            _rbt.removeBack();
    }

    /// Returns: A pointer to the value corresponding to this key, or null if not available.
    ///          Live builtin associative arrays.
    inout(V)* opBinaryRight(string op)(K key) inout if (op == "in")
    {
        if (!isInitialized)
            return null;

        auto kv = KeyValue(key, V.init);
        auto node = _rbt._find(kv);
        if (node is null)
            return null;
        else
            return &node.value.value;
    }

    /// Returns: A reference to the value corresponding to this key.
    ref inout(V) opIndex(K key) inout
    {
        inout(V)* p = key in this;
        return *p;
    }

    /// Updates a value associated with a key, creates it if necessary.
    void opIndexAssign(V value, K key)
    {
        // PERF: this could be faster
        V* p = key in this;
        if (p is null)
            insert(key, value);
        else
            *p = value;
    }

    /// Returns: `true` if this key is contained.
    bool contains(K key) const
    {
         if (!isInitialized)
            return false;
        auto kv = KeyValue(key, V.init);
        return (kv in _rbt);
    }

    /// Returns: Number of elements in the map.
    size_t length() const
    {
        if (!isInitialized)
            return 0;

        return _rbt.length();
    }

    /// Returns: `ttue` is the map has no element.
    bool empty() const
    {
        if (!isInitialized)
            return true;
        return _rbt.length() == 0;
    }

    // Iterate by value only

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
    }


private:

    alias Range(MapRangeType type) = MapRange!(RBNode!KeyValue*, type);
    alias ConstRange(MapRangeType type) = MapRange!(const(RBNode!KeyValue)*, type); /// Ditto
    alias ImmutableRange(MapRangeType type) = MapRange!(immutable(RBNode!KeyValue)*, type); /// Ditto

    alias _less = binaryFun!less;
    static bool lessForAggregate(const(KeyValue) a, const(KeyValue) b)
    {
        return _less(a.key, b.key);
    }

    alias InternalTree = RedBlackTree!(KeyValue, lessForAggregate, allowDuplicates);

    // we need a composite value to reuse Phobos RedBlackTree
    static struct KeyValue
    {
    nothrow:
    @nogc:
        K key;
        V value;
    }

    InternalTree _rbt;

    bool isInitialized() const
    {
        return _rbt !is null;
    }

    void lazyInitialize()
    {
        if (_rbt is null)
        {
            _rbt = mallocNew!InternalTree();
        }
    }
}

unittest
{
    // It should be possible to use most function of an uninitialized Map
    // All except functions returning a range will work.
    Map!(int, string) m;

    assert(m.length == 0);
    assert(m.empty);
    assert(!m.contains(7));

    auto range = m.byKey();
    assert(range.empty);
    foreach(e; range)
    {        
    }

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
         lazyInitialize();
    }

    @disable this(this);

    ~this()
    {
        if (isInitialized)
        {
            destroyFree(_rbt);
            _rbt = null;
        }
    }

    /// Insert an element in the container. 
    /// If allowDuplicates is false, this can fail and return `false` 
    /// if the already contains an element with equivalent key. 
    /// Returns: `true` if the insertion took place.
    bool insert(K key)
    {
        lazyInitialize();
        return _rbt.insert(key) != 0;
    }

    /// Removes an element from the container.
    /// Returns: `true` if the removal took place.
    bool remove(K key)
    {
        if (!isInitialized)
            return false;
        return _rbt.removeKey(key) != 0;
    }

    /// Removes all elements from the set.
    void clearContents()
    {
        if (!isInitialized)
            return;
        while(_rbt.length > 0)
            _rbt.removeBack();
    }

    /// Returns: `true` if the element is present.
    bool opBinaryRight(string op)(K key) inout if (op == "in")
    {
        if (!isInitialized)
            return false;
        return key in _rbt;
    }

    /// Returns: `true` if the element is present.
    bool opIndex(K key) const
    {
        if (!isInitialized)
            return false;
        return key in _rbt;
    }

    /// Returns: `true` if the element is present.
    bool contains(K key) const
    {
        if (!isInitialized)
            return false;
        return key in _rbt;
    }

    /// Fetch a range that spans all the elements in the container.
    auto opSlice() inout
    {
        if (!isInitialized)
            return nullRange();
        return _rbt[];
    }

    /// Returns: Number of elements in the set.
    size_t length() const
    {
        if (!isInitialized)
            return 0;
        return _rbt.length();
    }

    /// Returns: `ttue` is the set has no element.
    bool empty() const
    {
        if (!isInitialized)
            return true;
        return _rbt.length() == 0;
    }

private:
    alias InternalTree = RedBlackTree!(K, less, allowDuplicates); 
    InternalTree _rbt;

    bool isInitialized() const
    {
        return _rbt !is null;
    }

    void lazyInitialize()
    {
        if (_rbt is null)
        {
            _rbt = mallocNew!InternalTree();
        }
    }

    /**
    * Return a range without any items.
    */
    auto nullRange()
    {
        return InternalTree.Range.init;
    }

    /// Ditto
    auto nullRange() const
    {
        return InternalTree.ConstRange.init;
    }

    /// Ditto
    auto nullRange() immutable
    {
        return InternalTree.ImmutableRange.init;
    }
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

    auto range = set[];
    assert(range.empty);
    foreach(e; range)
    {        
    }

    // Finally create the internal state
    set.insert("titi");
    assert(set.contains("titi"));
}


unittest
{
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

}

private:


/*
* Implementation for a Red Black node for use in a Red Black Tree (see below)
*
* this implementation assumes we have a marker Node that is the parent of the
* root Node.  This marker Node is not a valid Node, but marks the end of the
* collection.  The root is the left child of the marker Node, so it is always
* last in the collection.  The marker Node is passed in to the setColor
* function, and the Node which has this Node as its parent is assumed to be
* the root Node.
*
* A Red Black tree should have O(lg(n)) insertion, removal, and search time.
*/
struct RBNode(V)
{
nothrow:
@nogc:
    /*
    * Convenience alias
    */
    alias Node = RBNode*;

    private Node _left;
    private Node _right;
    private Node _parent;

    /**
    * The value held by this node
    */
    V value;

    /**
    * Enumeration determining what color the node is.  Null nodes are assumed
    * to be black.
    */
    enum Color : byte
    {
        Red,
        Black
    }

    /**
    * The color of the node.
    */
    Color color;

    /**
    * Get the left child
    */
    @property inout(RBNode)* left() inout
    {
        return _left;
    }

    /**
    * Get the right child
    */
    @property inout(RBNode)* right() inout
    {
        return _right;
    }

    /**
    * Get the parent
    */
    @property inout(RBNode)* parent() inout
    {
        return _parent;
    }

    void deallocate()
    {
        //import core.stdc.stdio;
        //printf("deallocate %p\n", &this);
        destroyFree(&this);
    }

    /**
    * Set the left child.  Also updates the new child's parent node.  This
    * does not update the previous child.
    *
    * Returns newNode
    */
    @property Node left(Node newNode)
    {
        _left = newNode;
        if (newNode !is null)
            newNode._parent = &this;
        return newNode;
    }

    /**
    * Set the right child.  Also updates the new child's parent node.  This
    * does not update the previous child.
    *
    * Returns newNode
    */
    @property Node right(Node newNode)
    {
        _right = newNode;
        if (newNode !is null)
            newNode._parent = &this;
        return newNode;
    }

    // assume _left is not null
    //
    // performs rotate-right operation, where this is T, _right is R, _left is
    // L, _parent is P:
    //
    //      P         P
    //      |   ->    |
    //      T         L
    //     / \       / \
    //    L   R     a   T
    //   / \           / \
    //  a   b         b   R
    //
    /**
    * Rotate right.  This performs the following operations:
    *  - The left child becomes the parent of this node.
    *  - This node becomes the new parent's right child.
    *  - The old right child of the new parent becomes the left child of this
    *    node.
    */
    Node rotateR()
    {
        assert(_left !is null);

        // sets _left._parent also
        if (isLeftNode)
            parent.left = _left;
        else
            parent.right = _left;
        Node tmp = _left._right;

        // sets _parent also
        _left.right = &this;

        // sets tmp._parent also
        left = tmp;

        return &this;
    }

    // assumes _right is non null
    //
    // performs rotate-left operation, where this is T, _right is R, _left is
    // L, _parent is P:
    //
    //      P           P
    //      |    ->     |
    //      T           R
    //     / \         / \
    //    L   R       T   b
    //       / \     / \
    //      a   b   L   a
    //
    /**
    * Rotate left.  This performs the following operations:
    *  - The right child becomes the parent of this node.
    *  - This node becomes the new parent's left child.
    *  - The old left child of the new parent becomes the right child of this
    *    node.
    */
    Node rotateL()
    {
        assert(_right !is null);

        // sets _right._parent also
        if (isLeftNode)
            parent.left = _right;
        else
            parent.right = _right;
        Node tmp = _right._left;

        // sets _parent also
        _right.left = &this;

        // sets tmp._parent also
        right = tmp;
        return &this;
    }


    /**
    * Returns true if this node is a left child.
    *
    * Note that this should always return a value because the root has a
    * parent which is the marker node.
    */
    @property bool isLeftNode() const
    {
        assert(_parent !is null);
        return _parent._left is &this;
    }

    /**
    * Set the color of the node after it is inserted.  This performs an
    * update to the whole tree, possibly rotating nodes to keep the Red-Black
    * properties correct.  This is an O(lg(n)) operation, where n is the
    * number of nodes in the tree.
    *
    * end is the marker node, which is the parent of the topmost valid node.
    */
    void setColor(Node end)
    {
        // test against the marker node
        if (_parent !is end)
        {
            if (_parent.color == Color.Red)
            {
                Node cur = &this;
                while (true)
                {
                    // because root is always black, _parent._parent always exists
                    if (cur._parent.isLeftNode)
                    {
                        // parent is left node, y is 'uncle', could be null
                        Node y = cur._parent._parent._right;
                        if (y !is null && y.color == Color.Red)
                        {
                            cur._parent.color = Color.Black;
                            y.color = Color.Black;
                            cur = cur._parent._parent;
                            if (cur._parent is end)
                            {
                                // root node
                                cur.color = Color.Black;
                                break;
                            }
                            else
                            {
                                // not root node
                                cur.color = Color.Red;
                                if (cur._parent.color == Color.Black)
                                    // satisfied, exit the loop
                                    break;
                            }
                        }
                        else
                        {
                            if (!cur.isLeftNode)
                                cur = cur._parent.rotateL();
                            cur._parent.color = Color.Black;
                            cur = cur._parent._parent.rotateR();
                            cur.color = Color.Red;
                            // tree should be satisfied now
                            break;
                        }
                    }
                    else
                    {
                        // parent is right node, y is 'uncle'
                        Node y = cur._parent._parent._left;
                        if (y !is null && y.color == Color.Red)
                        {
                            cur._parent.color = Color.Black;
                            y.color = Color.Black;
                            cur = cur._parent._parent;
                            if (cur._parent is end)
                            {
                                // root node
                                cur.color = Color.Black;
                                break;
                            }
                            else
                            {
                                // not root node
                                cur.color = Color.Red;
                                if (cur._parent.color == Color.Black)
                                    // satisfied, exit the loop
                                    break;
                            }
                        }
                        else
                        {
                            if (cur.isLeftNode)
                                cur = cur._parent.rotateR();
                            cur._parent.color = Color.Black;
                            cur = cur._parent._parent.rotateL();
                            cur.color = Color.Red;
                            // tree should be satisfied now
                            break;
                        }
                    }
                }

            }
        }
        else
        {
            //
            // this is the root node, color it black
            //
            color = Color.Black;
        }
    }

    /**
    * Remove this node from the tree.  The 'end' node is used as the marker
    * which is root's parent.  Note that this cannot be null!
    *
    * Returns the next highest valued node in the tree after this one, or end
    * if this was the highest-valued node.
    */
    Node remove(Node end)
    {
        //
        // remove this node from the tree, fixing the color if necessary.
        //
        Node x;
        Node ret = next;

        // if this node has 2 children
        if (_left !is null && _right !is null)
        {
            //
            // normally, we can just swap this node's and y's value, but
            // because an iterator could be pointing to y and we don't want to
            // disturb it, we swap this node and y's structure instead.  This
            // can also be a benefit if the value of the tree is a large
            // struct, which takes a long time to copy.
            //
            Node yp, yl, yr;
            Node y = ret; // y = next
            yp = y._parent;
            yl = y._left;
            yr = y._right;
            auto yc = y.color;
            auto isyleft = y.isLeftNode;

            //
            // replace y's structure with structure of this node.
            //
            if (isLeftNode)
                _parent.left = y;
            else
                _parent.right = y;
            //
            // need special case so y doesn't point back to itself
            //
            y.left = _left;
            if (_right is y)
                y.right = &this;
            else
                y.right = _right;
            y.color = color;

            //
            // replace this node's structure with structure of y.
            //
            left = yl;
            right = yr;
            if (_parent !is y)
            {
                if (isyleft)
                    yp.left = &this;
                else
                    yp.right = &this;
            }
            color = yc;
        }

        // if this has less than 2 children, remove it
        if (_left !is null)
            x = _left;
        else
            x = _right;

        bool deferedUnlink = false;
        if (x is null)
        {
            // pretend this is a null node, defer unlinking the node
            x = &this;
            deferedUnlink = true;
        }
        else if (isLeftNode)
            _parent.left = x;
        else
            _parent.right = x;

        // if the color of this is black, then it needs to be fixed
        if (color == color.Black)
        {
            // need to recolor the tree.
            while (x._parent !is end && x.color == Node.Color.Black)
            {
                if (x.isLeftNode)
                {
                    // left node
                    Node w = x._parent._right;
                    if (w.color == Node.Color.Red)
                    {
                        w.color = Node.Color.Black;
                        x._parent.color = Node.Color.Red;
                        x._parent.rotateL();
                        w = x._parent._right;
                    }
                    Node wl = w.left;
                    Node wr = w.right;
                    if ((wl is null || wl.color == Node.Color.Black) &&
                        (wr is null || wr.color == Node.Color.Black))
                    {
                        w.color = Node.Color.Red;
                        x = x._parent;
                    }
                    else
                    {
                        if (wr is null || wr.color == Node.Color.Black)
                        {
                            // wl cannot be null here
                            wl.color = Node.Color.Black;
                            w.color = Node.Color.Red;
                            w.rotateR();
                            w = x._parent._right;
                        }

                        w.color = x._parent.color;
                        x._parent.color = Node.Color.Black;
                        w._right.color = Node.Color.Black;
                        x._parent.rotateL();
                        x = end.left; // x = root
                    }
                }
                else
                {
                    // right node
                    Node w = x._parent._left;
                    if (w.color == Node.Color.Red)
                    {
                        w.color = Node.Color.Black;
                        x._parent.color = Node.Color.Red;
                        x._parent.rotateR();
                        w = x._parent._left;
                    }
                    Node wl = w.left;
                    Node wr = w.right;
                    if ((wl is null || wl.color == Node.Color.Black) &&
                        (wr is null || wr.color == Node.Color.Black))
                    {
                        w.color = Node.Color.Red;
                        x = x._parent;
                    }
                    else
                    {
                        if (wl is null || wl.color == Node.Color.Black)
                        {
                            // wr cannot be null here
                            wr.color = Node.Color.Black;
                            w.color = Node.Color.Red;
                            w.rotateL();
                            w = x._parent._left;
                        }

                        w.color = x._parent.color;
                        x._parent.color = Node.Color.Black;
                        w._left.color = Node.Color.Black;
                        x._parent.rotateR();
                        x = end.left; // x = root
                    }
                }
            }
            x.color = Node.Color.Black;
        }

        if (deferedUnlink)
        {
            //
            // unlink this node from the tree
            //
            if (isLeftNode)
                _parent.left = null;
            else
                _parent.right = null;
        }

        // clean references to help GC - Bugzilla 12915
        _left = _right = _parent = null;

        return ret;
    }

    /**
    * Return the leftmost descendant of this node.
    */
    @property inout(RBNode)* leftmost() inout
    {
        inout(RBNode)* result = &this;
        while (result._left !is null)
            result = result._left;
        return result;
    }

    /**
    * Return the rightmost descendant of this node
    */
    @property inout(RBNode)* rightmost() inout
    {
        inout(RBNode)* result = &this;
        while (result._right !is null)
            result = result._right;
        return result;
    }

    /**
    * Returns the next valued node in the tree.
    *
    * You should never call this on the marker node, as it is assumed that
    * there is a valid next node.
    */
    @property inout(RBNode)* next() inout
    {
        inout(RBNode)* n = &this;
        if (n.right is null)
        {
            while (!n.isLeftNode)
                n = n._parent;
            return n._parent;
        }
        else
            return n.right.leftmost;
    }

    /**
    * Returns the previous valued node in the tree.
    *
    * You should never call this on the leftmost node of the tree as it is
    * assumed that there is a valid previous node.
    */
    @property inout(RBNode)* prev() inout
    {
        inout(RBNode)* n = &this;
        if (n.left is null)
        {
            while (n.isLeftNode)
                n = n._parent;
            return n._parent;
        }
        else
            return n.left.rightmost;
    }
}

// Range type for RedBlackTree
private struct RBRange(N)
{
nothrow:
@nogc:
    alias Node = N;
    alias Elem = typeof(Node.value);

    private Node _begin = null;
    private Node _end = null;

    private this(Node b, Node e)
    {
        _begin = b;
        _end = e;
    }

    /**
    * Returns $(D true) if the range is _empty
    */
    @property bool empty() const
    {
        return _begin is _end;
    }

    /**
    * Returns the first element in the range
    */
    @property Elem front()
    {
        return _begin.value;
    }

    /**
    * Returns the last element in the range
    */
    @property Elem back()
    {
        return _end.prev.value;
    }

    /**
    * pop the front element from the range
    *
    * complexity: amortized $(BIGOH 1)
    */
    void popFront()
    {
        _begin = _begin.next;
    }

    /**
    * pop the back element from the range
    *
    * complexity: amortized $(BIGOH 1)
    */
    void popBack()
    {
        _end = _end.prev;
    }

    /**
    * Trivial _save implementation, needed for $(D isForwardRange).
    */
    @property RBRange save()
    {
        return this;
    }
}

unittest
{
    // RBRange.init is supposed to be an empty valid range
    RBRange!(RBNode!int*) range;
    assert(range.empty);
    foreach(e; range)
    {        
    }
}

private enum MapRangeType
{
    key,
    value,
    keyValue
}

// Range type for Dplug's Map, can iterate on keys or values
private struct MapRange(N, MapRangeType type)
{
nothrow:
@nogc:

    alias Node = N;
    alias InnerRange = RBRange!N;

    static if (type == MapRangeType.key)
        alias Elem = typeof(Node.value.key);

    else static if (type == MapRangeType.value)
        alias Elem = typeof(Node.value.value);

    else static if (type == MapRangeType.keyValue)
        alias Elem = typeof(Node.value);

    static Elem get(InnerRange.Elem pair)
    {
        static if (type == MapRangeType.key)
            return pair.key;

        else static if (type == MapRangeType.value)
            return pair.value;

        else static if (type == MapRangeType.keyValue)
            return pair;
    }

    // A Map range is just a wrapper around a RBRange
    private InnerRange _inner;

    private this(InnerRange inner)
    {
        _inner = inner;
    }

    /**
    * Returns $(D true) if the range is _empty
    */
    @property bool empty() const
    {
        return _inner.empty;
    }

    /**
    * Returns the first element in the range
    */
    @property Elem front()
    {
        return get(_inner.front);
    }

    /**
    * Returns the last element in the range
    */
    @property Elem back()
    {
        return get(_inner.back());
    }

    /**
    * pop the front element from the range
    *
    * complexity: amortized $(BIGOH 1)
    */
    void popFront()
    {
        _inner.popFront();
    }

    /**
    * pop the back element from the range
    *
    * complexity: amortized $(BIGOH 1)
    */
    void popBack()
    {
        _inner.popBack();
    }

    /**
    * Trivial _save implementation, needed for $(D isForwardRange).
    */
    @property MapRange save()
    {
        return this;
    }
}

/**
* Implementation of a $(LINK2 https://en.wikipedia.org/wiki/Red%E2%80%93black_tree,
* red-black tree) container.
*
* All inserts, removes, searches, and any function in general has complexity
* of $(BIGOH lg(n)).
*
* To use a different comparison than $(D "a < b"), pass a different operator string
* that can be used by $(REF binaryFun, std,functional), or pass in a
* function, delegate, functor, or any type where $(D less(a, b)) results in a $(D bool)
* value.
*
* Note that less should produce a strict ordering.  That is, for two unequal
* elements $(D a) and $(D b), $(D less(a, b) == !less(b, a)). $(D less(a, a)) should
* always equal $(D false).
*
* If $(D allowDuplicates) is set to $(D true), then inserting the same element more than
* once continues to add more elements.  If it is $(D false), duplicate elements are
* ignored on insertion.  If duplicates are allowed, then new elements are
* inserted after all existing duplicate elements.
*/

final class RedBlackTree(T, alias less = "a < b", bool allowDuplicates = false)
{
nothrow:
@nogc:
    /**
    * Element type for the tree
    */
    alias Elem = T;

    alias _less = binaryFun!less;

    // used for convenience
    private alias RBNode = .RBNode!Elem;
    private alias Node = RBNode.Node;

    private Node   _end;
    private Node   _begin;
    private size_t _length;

    private void _setup()
    {
        assert(!_end); //Make sure that _setup isn't run more than once.
        _begin = _end = allocate();
    }

    static private Node allocate()
    {
        Node p = mallocNew!RBNode;
        //import core.stdc.stdio;
        //printf("allocate %p\n", p);
        return p;
    }

    static private Node allocate(Elem v)
    {
        auto result = allocate();
        result.value = v;
        return result;
    }

    /**
    * The range types for $(D RedBlackTree)
    */
    alias Range = RBRange!(RBNode*);
    alias ConstRange = RBRange!(const(RBNode)*); /// Ditto
    alias ImmutableRange = RBRange!(immutable(RBNode)*); /// Ditto

    // find a node based on an element value
    private inout(RBNode)* _find(Elem e) inout
    {
        static if (allowDuplicates)
        {
            inout(RBNode)* cur = _end.left;
            inout(RBNode)* result = null;
            while (cur)
            {
                if (_less(cur.value, e))
                    cur = cur.right;
                else if (_less(e, cur.value))
                    cur = cur.left;
                else
                {
                    // want to find the left-most element
                    result = cur;
                    cur = cur.left;
                }
            }
            return result;
        }
        else
        {
            inout(RBNode)* cur = _end.left;
            while (cur)
            {
                if (_less(cur.value, e))
                    cur = cur.right;
                else if (_less(e, cur.value))
                    cur = cur.left;
                else
                    return cur;
            }
            return null;
        }
    }

    // add an element to the tree, returns the node added, or the existing node
    // if it has already been added and allowDuplicates is false
    private auto _add(Elem n)
    {
        Node result;
        static if (!allowDuplicates)
            bool added = true;

        if (!_end.left)
        {
            _end.left = _begin = result = allocate(n);
        }
        else
        {
            Node newParent = _end.left;
            Node nxt;
            while (true)
            {
                if (_less(n, newParent.value))
                {
                    nxt = newParent.left;
                    if (nxt is null)
                    {
                        //
                        // add to right of new parent
                        //
                        newParent.left = result = allocate(n);
                        break;
                    }
                }
                else
                {
                    static if (!allowDuplicates)
                    {
                        if (!(_less(newParent.value, n)))
                        {
                            result = newParent;
                            added = false;
                            break;
                        }
                    }
                    nxt = newParent.right;
                    if (nxt is null)
                    {
                        //
                        // add to right of new parent
                        //
                        newParent.right = result = allocate(n);
                        break;
                    }
                }
                newParent = nxt;
            }
            if (_begin.left)
                _begin = _begin.left;
        }

        static if (allowDuplicates)
        {
            result.setColor(_end);
            ++_length;
            return result;
        }
        else
        {
            import std.typecons : Tuple;

            if (added)
            {
                ++_length;
                result.setColor(_end);
            }
            return Tuple!(bool, "added", Node, "n")(added, result);
        }
    }


    /**
    * Check if any elements exist in the container.  Returns $(D false) if at least
    * one element exists.
    */
    @property bool empty()
    {
        return _end.left is null;
    }

    /++
    Returns the number of elements in the container.

    Complexity: $(BIGOH 1).
    +/
    @property size_t length() const
    {
        return _length;
    }

    // Find the range for which every element is equal.
    private void findEnclosingRange(Elem e, inout(RBNode)** begin, inout(RBNode)** end) inout
    {
        *begin = _firstGreaterEqual(e);
        *end = _firstGreater(e);
    }

    /**
    * Fetch a range that spans all the elements in the container.
    *
    * Complexity: $(BIGOH 1)
    */
    Range opSlice()
    {
        return Range(_begin, _end);
    }

    /// Ditto
    ConstRange opSlice() const
    {
        return ConstRange(_begin, _end);
    }

    /// Ditto
    ImmutableRange opSlice() immutable
    {
        return ImmutableRange(_begin, _end);
    }

    /**
    * Fetch a range that spans all equal elements of a particular value.
    *
    * Complexity: $(BIGOH 1)
    */
    Range range(Elem e)
    {
        RBNode* begin, end;
        findEnclosingRange(e, &begin, &end);
        return Range(begin, end);
    }

    /// Ditto
    ConstRange range(Elem e) const
    {
        const(RBNode)* begin, end;
        findEnclosingRange(e, &begin, &end);
        return ConstRange(begin, end);
    }

    /// Ditto
    ImmutableRange range(Elem e) immutable
    {
        immutable(RBNode)* begin, end;
        findEnclosingRange(e, &begin, &end);
        return ImmutableRange(begin, end);
    }

    /**
    * The front element in the container
    *
    * Complexity: $(BIGOH 1)
    */
    Elem front()
    {
        return _begin.value;
    }

    /**
    * The last element in the container
    *
    * Complexity: $(BIGOH log(n))
    */
    Elem back()
    {
        return _end.prev.value;
    }

    /++
    $(D in) operator. Check to see if the given element exists in the
    container.

    Complexity: $(BIGOH log(n))
    +/
    bool opBinaryRight(string op)(Elem e) const if (op == "in")
    {
        return _find(e) !is null;
    }

    /**
    * Insert a single element in the container.  Note that this does not
    * invalidate any ranges currently iterating the container.
    *
    * Returns: The number of elements inserted.
    *
    * Complexity: $(BIGOH log(n))
    */
    size_t stableInsert(Elem elem)
    {
        static if (allowDuplicates)
        {
            _add(elem);
            return 1;
        }
        else
        {
            return(_add(elem).added ? 1 : 0);
        }
    }

    /// ditto
    alias insert = stableInsert;

    /**
    * Remove an element from the container and return its value.
    *
    * Complexity: $(BIGOH log(n))
    */
    Elem removeAny()
    {
        scope(success)
            --_length;
        auto n = _begin;
        auto result = n.value;
        _begin = n.remove(_end);
        n.deallocate();
        return result;
    }

    /**
    * Remove the front element from the container.
    *
    * Complexity: $(BIGOH log(n))
    */
    void removeFront()
    {
        scope(success)
            --_length;
        auto oldBegin = _begin;
        _begin = _begin.remove(_end);
        oldBegin.deallocate();
    }

    /**
    * Remove the back element from the container.
    *
    * Complexity: $(BIGOH log(n))
    */
    void removeBack()
    {
        scope(success)
            --_length;
        auto lastnode = _end.prev;
        if (lastnode is _begin)
        {
            auto oldBegin = _begin;
            _begin = _begin.remove(_end);
            oldBegin.deallocate();
        }
        else
        {
            lastnode.remove(_end);
            lastnode.deallocate();
        }
    }

    /++ Ditto +/
    size_t removeKey(Elem e)
    {
        immutable lenBefore = length;

        auto beg = _firstGreaterEqual(e);
        if (beg is _end || _less(e, beg.value))
            // no values are equal
            return 0;
        auto oldBeg = beg;
        immutable isBegin = (beg is _begin);
        beg = beg.remove(_end);
        if (isBegin)
            _begin = beg;
        --_length;

        oldBeg.deallocate();

        return lenBefore - length;
    }

    // find the first node where the value is > e
    private inout(RBNode)* _firstGreater(Elem e) inout
    {
        // can't use _find, because we cannot return null
        auto cur = _end.left;
        inout(RBNode)* result = _end;
        while (cur)
        {
            if (_less(e, cur.value))
            {
                result = cur;
                cur = cur.left;
            }
            else
                cur = cur.right;
        }
        return result;
    }


    // find the first node where the value is >= e
    private inout(RBNode)* _firstGreaterEqual(Elem e) inout
    {
        // can't use _find, because we cannot return null.
        auto cur = _end.left;
        inout(RBNode)* result = _end;
        while (cur)
        {
            if (_less(cur.value, e))
                cur = cur.right;
            else
            {
                result = cur;
                cur = cur.left;
            }

        }
        return result;
    }

    ///
    this()
    {
        _setup();
    }

    ~this()
    {
        while(length > 0)
            removeBack();

        // deallocate sentinel
        _end.deallocate();
    }
}
