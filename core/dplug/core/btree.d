/**
    Vanilla B-Tree implementation.
    Note that this is an implementation detail of
    `dplug.core.map` and not part of of the Dplug API.

    Copyright: (c) Guillaume Piolat 2024-2025.
    License: [BSL-1.0](http://www.boost.org/LICENSE_1_0.txt)
*/
module dplug.core.btree;

import dplug.core.nogc;

import std.functional: binaryFun;

//debug = btree;

debug(btree)
{
    import core.stdc.stdio;
}

/**
    Vanilla [B-Tree](https://en.wikipedia.org/wiki/B-tree).

    `O(lg(n))` insertion, removal, and search time, much
    like the builtin associative arrays.

    `.init` is valid, needs no initialization.

    Params:
        K    = Key type, must be comparable with `less`.
        V    = Value type.
        less = Must be a strict inequality, orders all `K`.
        allowDuplicates = Are duplicate keys allowed?
        duplicateKeyIsUB = Are duplicate keys UB?
                           When `true`, user MUST guarantee
                           no duplicates and `insert` is
                           faster.

    Warning: keys don't need `opEquals`, but:
         `!(a < b) && !(b > a)`
         should imply that:
         `a == b`
*/
struct BTree(K, V, alias less = "a < b",
             bool allowDuplicates = false,
             bool duplicateKeyIsUB = false)
{
public:
nothrow:
@nogc:

    // TODO: map over range of keys
    // PERF: tune minDegree vs size of K and V, there must
    // be a sweet spot
    // PERF: allocate nodes in memory pool, to be built in
    //       bulk. How does reclaim works in that case, in a
    //       way that doesn't explode memory?
    // PERF: first node could be interned in the struct
    //       itself (interior pointer) however that requires
    //       first to tweak the branching factor with size
    //       of item.
    // PERF: (requires: Node memory pool) find a way to
    //       deallocate all at once.
    // PERF: find how to use duplicateKeyIsUB for Map and
    //       Set.

    debug(btree) invariant()
    {
        checkInvariant();
    }


    /**
        Not copyable.
    */
    @disable this(this);


    /**
        Constructor.
        A new B-tree has no allocation and zero items.
    */
    this(int dummy)
    {
        // It does nothing, because T.init is valid.
    }


    /**
        Destructor. All nodes cleared.
    */
    ~this()
    {
        if (_root)
        {
            _root.reclaimMemory();
            _root = null;
        }
    }


    /**
        Number of items in the B-Tree.
        Returns: Number of items.
    */
    size_t length() const
    {
        return _count;
    }


    /**
        Is this B-Tree empty?
        Returns: `true` if zero items.
    */
    bool empty() const
    {
        return _count == 0;
    }


    /**
        Insert item in tree.

        Params:
            key   = Key to insert.
            value = Value to insert associated with `key`.

        Returns: `true` if the insertion took place.

        Warning: Inserting duplicate keys when duplicates
                 are not supported is Undefined Behaviour.
                 Use `contains()` to avoid that case.
    */
    bool insert(K key, V value)
    {
        lazyInitialize();

        // Runtime check to prevent accidental dupe keys.
        static if (!allowDuplicates)
        {
            static if (duplicateKeyIsUB)
            {
                // Detect dupes, but in -release it will
                // be Undefined Behaviour
                assert(findKeyValue(_root, key) is null);
            }
            else
            {
                // Always detect dupes, this slows down
                // insertion by a lot
                if (findKeyValue(_root, key) !is null)
                    return false;
            }
        }

        Node* r = _root;

        if (r.isFull())
        {
            Node* s = allocateNode();
            _root = s;
            s.parent = null;
            s.isLeaf = false;
            s.numKeys = 0;
            s.children[0] = r;
            r.parent = s;
            splitChild(s, 0, r);
            insertNonFull(s, key, value);
        }
        else
        {
            insertNonFull(r, key, value);
        }

        _count += 1;
        return true;
    }


    /**
        Erase an item from the tree.

        Params:
            key = Key to remove.

        Returns: Number of removed items, can be 0 or 1. In
                 case of dupe keys, remove only one of them.
    */
    size_t remove(K key)
    {
        // This was surprisingly undocumented on the
        // Internet or LLM.

        if (_root is null)
            return 0;

        int keyIndex;
        Node* node = findNode(_root, key, keyIndex);
        if (node is null)
            return 0; // not found

        _count -= 1;

        // Reference:
        // https://www.youtube.com/watch?v=0NvlyJDfk1M
        if (node.isLeaf)
        {
            // First, remove key, then eventually rebalance.
            deleteKeyValueAtIndexAndShift(node, keyIndex);
            rebalanceAfterDeletion(node);
        }
        else
        {
            // Exchange key with either highest of the
            // smaller key in leaf, or largest of the
            // highest keys.
            //
            //              . value .
            //             /         \
            //            /           \
            //           /             \
            //     left subtree      right subtree
            //
            // But I'm not sure why people tout this
            // solution.
            // Here we simply always get to the rightmost
            // leaf node of left subtree. It seems it's
            // always possible indeed, and it's not faster
            // to look at the other sub-tree.
            Node* leaf = node.children[keyIndex];
            while (!leaf.isLeaf)
                leaf = leaf.children[leaf.numKeys];
            assert(leaf);

            // Remove key from leaf, put it instead of
            // target.
            node.kv[keyIndex] = leaf.kv[leaf.numKeys-1];
            leaf.numKeys -= 1;

            // and then rebalance
            rebalanceAfterDeletion(leaf);
        }
        return 1;
    }


    /**
        Iterate over all values in the tree.

        Returns: Forward range of `V`, over the whole tree.
    */
    auto byValue()
    {
        return BTreeRange!(RangeType.value)(this);
    }
    ///ditto
    auto byValue() const
    {
        return const(BTreeRange!(RangeType.value))(this);
    }

    /**
        Iterate over all keys in the tree.

        Returns: Forward range of `K`, over the whole tree.
    */
    auto byKey()
    {
        return BTreeRange!(RangeType.key)(this);
    }
    ///ditto
    auto byKey() const
    {
        return const(BTreeRange!(RangeType.key))(this);
    }

    /**
        Iterate over all keys and values simultaneously.

        Returns: Forward range of a Voldemort struct that
                 exposes `.key` and `.value` of type `K` and
                 `V` respectively.
    */
    auto byKeyValue()
    {
        return BTreeRange!(RangeType.keyValue)(this);
    }
    ///ditto
    auto byKeyValue() const
    {
        return const(BTreeRange!(RangeType.keyValue))(this);
    }


    /**
        Search the B-Tree by key.

        Params:
            key = Key to search for.

        Returns:
            A pointer to the corresponding `V` value.
            `null` if not found.

        Note: In case of duplicate keys, it returns one
              of those in unspecified order.
    */
    inout(V)* opBinaryRight(string op)(K key) inout
        if (op == "in")
    {
        if (_root is null)
            return null;
        inout(KeyValue)* kv = findKeyValue(_root, key);
        if (!kv) return null;
        return &kv.value;
    }

    /**
        Search the B-Tree by key.

        Params:
            key = Key to search for.

        Returns: A reference to the value corresponding to
                 this key.

        Note: In case of duplicate keys, it returns one
              of those in unspecified order.
    */
    ref inout(V) opIndex(K key) inout
    {
        inout(V)* p = key in this;
        return *p;
    }

    /**
        Search the B-Tree for a key.

        Params:
            key = Key to search for.

        Returns: `true` if `key`` is contained in the tree.
    */
    bool contains(K key) const
    {
        if (_root is null)
            return false;
        return findKeyValue(_root, key) !is null;
    }

private:

    // Called "t" or "minimum degree" in litterature, can
    // never be < 2.
    // Make it lower (eg: 2) to test tree algorithms.
    // See <digression> below to see why this is not B-Tree
    // "order".
    enum minDegree = 16;

    // Every node must have >= minKeysPerNode and <=
    // maxKeysPerNode.
    // The root node is allowed to have < minKeysPerNode
    // (but not zero).
    enum int minKeys     =     minDegree - 1;
    enum int maxKeys     = 2 * minDegree - 1;
    enum int minChildren =     minDegree;
    enum int maxChildren = 2 * minDegree;

    alias _less = binaryFun!less;

    Node* _root;
    size_t _count;

    void checkInvariant() const
    {
        int count = 0;
        if (_root)
        {
            assert(_count > 0);
            checkNode(_root, null, count);
        }
        else
        {
            assert(_count == 0); // No items <=> null _root
        }
        assert(count == _count);
    }

    // null if not found
    inout(KeyValue)* findKeyValue(inout(Node)* x, K key)
        inout
    {
        int index;
        inout(Node)* node = findNode(x, key, index);
        if (node is null)
            return null;
        else
            return &(node.kv[index]);
    }

    // Return containing node + index of value in store, or
    // null if not found.
    inout(Node)* findNode(inout(Node)* x, K key,
                          out int index) inout
    {
        int i = 0;
        while (i < x.numKeys && _less(x.kv[i].key, key))
            i += 1;

        // Like in Phobos' Red Black tree, this use:
        // !less(a,b) && !less(b,a) instead of opEquals.

        if (i < x.numKeys && !_less(key, x.kv[i].key))
        {
            index = i;
            return x;
        }
        else
        {
            if (x.isLeaf)
                return null;
            else
                return findNode(x.children[i], key, index);
        }
    }

    // Create root node if none.
    void lazyInitialize()
    {
        if (_root)
            return;

        _root = allocateNode;
        _root.isLeaf = true;
        _root.numKeys = 0;
        _root.parent = null;
    }

    void insertNonFull(Node* x, K key, V value)
    {
        int i = x.numKeys - 1;
        if (x.isLeaf)
        {
            while (i >= 0 && _less(key, x.kv[i].key))
            {
                x.kv[i+1] = x.kv[i];
                i -= 1;
            }
            x.kv[i+1] = KeyValue(key, value);
            x.numKeys++;
        }
        else
        {
            while (i >= 0 && _less(key, x.kv[i].key))
            {
                i -= 1;
            }
            i += 1;
            Node* c = x.children[i];
            if (c.isFull)
            {
                splitChild(x, i, c);
                if (_less(x.kv[i].key, key))
                {
                    i = i + 1;
                    c = x.children[i];
                }
            }
            insertNonFull(c, key, value);
        }
    }

    // x = a parent with at least one slot available
    // y = a full node to split
    void splitChild(Node* x, int i, Node* y)
    {
        // create new child, that will take half the
        // keyvalues and children of the full y node
        Node* z = allocateNode();
        z.isLeaf = y.isLeaf;
        z.numKeys = minDegree - 1;
        z.parent = x;

        // copy half of values (highest) in new child
        for (int j = 0; j < minDegree - 1; ++j)
        {
            z.kv[j] = y.kv[minDegree + j];
        }

        // same for child pointer if any
        if (!y.isLeaf)
        {
            for (int j = 0; j < minDegree; ++j)
            {
                z.children[j] = y.children[minDegree + j];
                z.children[j].parent = z;
            }
        }

        // Formerly full child now has room again
        y.numKeys = minDegree - 1;

        // And now for the parent node:
        // * new child is inserted right of its older
        //   sibling
        for (int j = x.numKeys; j > i; --j)
        {
            x.children[j+1] = x.children[j];
        }
        x.children[i+1] = z;
        for (int j = x.numKeys - 1; j >= i; --j)
        {
            x.kv[j+1] = x.kv[j];
        }
        // * middle key is choosen as pivot
        x.kv[i] = y.kv[minDegree-1];
        x.numKeys += 1;
    }

    // Take one node that is exactly below capacity, and
    // reinstate the invariant by merging nodes and
    // exchanging with neighbours. Is called on nodes that
    // might be missing exactly one item.
    void rebalanceAfterDeletion(Node* node)
    {
        if (node.parent is null)  // is this the tree _root?
        {
            assert(_root is node);

            if (_root.numKeys == 0)
            {
                if (_root.isLeaf) // no more items in tree
                {
                    destroyFree(_root);
                    _root = null;
                }
                else // tree is reduced by one level
                {
                    Node* oldRoot = _root;
                    _root = oldRoot.children[0];
                    _root.parent = null;
                    oldRoot.numKeys = -1;
                    // so that it is not destroyed
                    oldRoot.children[0] = null;
                    destroyFree(oldRoot); // <- here
                }
            }
            return;
        }

        if (node.numKeys >= minKeys)
            return; // no balance issue, exit

        // Else, the node is missing one key
        assert(node.numKeys == minKeys - 1);

        Node* parent = node.parent;
        assert(parent !is null);

        Node* left;
        Node* right;
        int childIndex = -1;
        for (int n = 0; n < parent.numChildren; ++n)
        {
            if (parent.children[n] == node)
            {
                childIndex = n;
                break;
            }
        }

        // has left sibling?
        if (childIndex != 0)
            left = parent.children[childIndex-1];

        // has right sibling?
        if (childIndex + 1 < parent.numChildren)
            right = parent.children[childIndex+1];

        assert(left || right); // one of those exists

        if (left && left.numKeys > minKeys)
        {
            // Take largest key from left sibling, it
            // becomes the new pivot in parent. Old pivot
            // erase our key (and if non-leaf, gets the left
            // sibling right subtree + the node one child).
            assert(left.isLeaf == node.isLeaf);
            KeyValue largest = left.kv[left.numKeys - 1];
            Node* rightMost = left.children[left.numKeys];
            left.numKeys -= 1;
            KeyValue pivot = node.parent.kv[childIndex-1];
            node.parent.kv[childIndex-1] = largest;

            // Pivot enter at position 0.
            // Need to shift a few kv.
            for (int n = minKeys - 1; n > 0; --n)
            {
                node.kv[n] = node.kv[n-1];
            }
            node.kv[0] = pivot;
            if (!node.isLeaf)
            {
                for (int n = minKeys; n > 0; --n)
                {
                    node.children[n] = node.children[n-1];
                }
                node.children[0] = rightMost;
                rightMost.parent = node;
            }
            node.numKeys = minKeys;
        }
        else if (right && right.numKeys > minKeys)
        {
            // Take smallest key from right sibling, it
            // becomes the new pivot in parent. Old pivot
            // erase our key.
            assert(right.isLeaf == node.isLeaf);
            KeyValue smallest = right.kv[0];
            Node* leftMostChild = right.children[0];

            // Delete first key (and first child, if any) of
            // right sibling.
            if (!node.isLeaf)
            {
                for (int n = 0; n < right.numKeys; ++n)
                    right.children[n] = right.children[n+1];
            }
            deleteKeyValueAtIndexAndShift(right, 0);

            KeyValue pivot = parent.kv[childIndex];
            parent.kv[childIndex] = smallest;
            node.kv[minKeys - 1] = pivot;
            if (!node.isLeaf)
            {
                leftMostChild.parent = node;
                node.children[minKeys] = leftMostChild;
            }
            node.numKeys = minKeys;
        }
        else
        {
            // merge with either left or right
            if (right)
            {
                mergeChild(parent, childIndex);
            }
            else if (left)
            {
                mergeChild(parent, childIndex - 1);
            }
            else
                assert(0);
        }
    }

    // Merge children nth and nth+1, which must both have
    // min amount of keys. makes one node with max amount of
    // keys
    void mergeChild(Node* parent, int nth)
    {
        Node* left = parent.children[nth];
        Node* right = parent.children[nth+1];
        KeyValue pivot = parent.kv[nth];
        assert(left.isLeaf == right.isLeaf);

        // One key is missing already
        assert(left.numKeys + right.numKeys == 2*minKeys-1);

        left.kv[left.numKeys] = pivot;

        for (int n = 0; n < right.numKeys; ++n)
        {
            left.kv[left.numKeys + 1 + n] = right.kv[n];
        }
        if (!left.isLeaf)
        {
            for (int n = 0; n < right.numKeys+1; ++n)
            {
                left.children[left.numKeys + 1 + n] =
                    right.children[n];
                assert(right.children[n].parent == right);
                left.children[left.numKeys + 1 + n].parent =
                     left;
            }
        }
        left.numKeys = 2 * minKeys;

        // in parent, shift all by one
        parent.numKeys -= 1;
        for (int n = nth; n < parent.numKeys; ++n)
        {
            parent.kv[n]         = parent.kv[n+1];
            parent.children[n+1] = parent.children[n+2];
        }

        // in case the parent has too few items
        rebalanceAfterDeletion(parent);

        destroyFree(right);
    }

    // internal use, delete a kv and shift remaining kv
    void deleteKeyValueAtIndexAndShift(Node* node,
                                       int index)
    {
        node.numKeys -= 1;
        for (int n = index; n < node.numKeys; ++n)
        {
            node.kv[n] = node.kv[n+1];
        }
    }

    // node invariant
    void checkNode(const(Node)* node,
                   const(Node)* parent,
                   ref int count) const
    {
        // Each node of the tree except the root must
        // contain at least
        // `minDegree − 1` keys (and hence must have at
        // least `minDegree` children if it is not a leaf).
        if (parent !is null)
        {
            assert(node.numKeys >= minKeys);
            assert(node.numKeys <= maxKeys);

            // parent can't be a leaf
            assert(!parent.isLeaf);
        }
        else
        {
            assert(node.numKeys >= 1);
        }

        assert(parent is node.parent);

        count += node.numKeys;

        if (!node.isLeaf)
        {
            // Check child invariants.
            for (int n = 0; n < node.numChildren(); ++n)
            {
                checkNode(node.children[n], node, count);
            }

            // Check internal key ordering
            for (int n = 0; n + 1 < node.numKeys; ++n)
            {
                const(K) k1 = node.kv[n].key;
                const(K) k2 = node.kv[n+1].key;
                static if (allowDuplicates)
                {
                    assert(! _less(k2, k1));
                }
                else
                {
                    assert(_less(k1, k2));
                }
            }

            // Check key orderings with children. All keys
            // of child must be inside parent range.
            for (int n = 0; n < node.numKeys; ++n)
            {
                const(K) k = node.kv[n].key;

                // All key of left children must be smaller,
                // right must be larger.
                const(Node)* left = node.children[n];
                const(Node)* right = node.children[n+1];

                for (int m = 0; m < left.numKeys; ++m)
                {
                    static if (allowDuplicates)
                        assert(! _less(k, left.kv[m].key));
                    else
                        assert(_less(left.kv[m].key, k));
                }

                for (int m = 0; m < right.numKeys; ++m)
                {
                    static if (allowDuplicates)
                        assert(!_less(right.kv[m].key, k));
                    else
                        assert(_less(k, right.kv[m].key));
                }
            }
        }
    }

    static struct KeyValue
    {
        K key;
        V value;
    }

    debug(btree)
    public void display()
    {
        printf("Tree has %zu items\n", _count);
        if (_root)
            _root.display();
        else
        {
            printf("    * no root\n");
        }
    }

    Node* allocateNode()
    {
        Node* node = mallocNew!Node();
        node.treeRef = &this;
        return node;
    }

    void deallocateNode(Node* node)
    {
        destroyFree!Node(node);
    }


    static struct Node
    {
    nothrow @nogc:
        // Is this a leaf node?
        bool isLeaf;

        // This node stores:
        //   - numKeys keys,
        //   - and numKeys+1 children.
        int numKeys;

        // Keys and values together.
        KeyValue[maxKeys] kv;

        // (borrowed) Parent node.
        // Is null for the root.
        Node* parent;

        // (owning) Pointer to child nodes.
        Node*[maxChildren] children;

        BTree* treeRef;

        /// Number of children = numKeys + 1
        int numChildren() const
        {
            assert(!isLeaf); // leaves have no child
            return numKeys + 1;
        }

        bool isFull() const
        {
            return numKeys == maxKeys;
        }

        void reclaimMemory()
        {
            if (isLeaf)
                return;

            for (int c = 0; c < numChildren(); ++c)
            {
                children[c].reclaimMemory();
            }

            treeRef.deallocateNode(&this);
        }

        debug(btree)
        void display()
        {
            printf("\nNode %p\n", &this);
            printf("   * parent = %p\n", parent);
            printf("   * leaf = %s\n", isLeaf ? "yes".ptr:
                                                "no".ptr);
            printf("   * numKeys = %d\n", numKeys);

            if (numKeys > 0)
            {
                for (int v = 0; v < numKeys; ++v)
                {
                    static if (is(V == string))
                        printf(" - key %d and value %s\n",
                               kv[v].key, kv[v].value.ptr);
                    else
                        printf(" - key %d\n", kv[v].key);
                }
            }
            if (!isLeaf)
            {
                for (int v = 0; v < numKeys+1; ++v)
                {
                    printf(" - => child %p\n", children[v]);
                }
            }
            printf("\n");

            if (!isLeaf)
            {
                for (int v = 0; v < numKeys+1; ++v)
                {
                    children[v].display;
                }
            }
        }
    }


public:

    enum RangeType
    {
        key,
        value,
        keyValue
    }

    /// Btree Range
    static struct BTreeRange(RangeType type)
    {
    nothrow @nogc:
        this(ref BTree tree)
        {
            _current = tree._root;
            if (_current is null)
                return;
            while(!_current.isLeaf)
                _current = _current.children[0];
        }

        this(ref const(BTree) tree)
        {
            // const_cast here
            _current = cast(Node*)(tree._root);
            if (_current is null)
                return;
            while(!_current.isLeaf)
                _current = _current.children[0];
        }

        bool empty() const
        {
            return _current is null;
        }

        auto front()
        {
            static if (type == RangeType.key)
                return _current.kv[_curItem].key;
            static if (type == RangeType.value)
                return _current.kv[_curItem].value;
            static if (type == RangeType.keyValue)
                return _current.kv[_curItem];
        }

        void popFront()
        {
            // Basically, _current and _curItem points
            // at a key.
            //
            //       3
            //     /   \
            //  1-2     4-5
            //
            //  Case 1: increment _curItem
            //  Case 2: increment _curItem, see that
            //          it's out of bounds.
            //          Go up the parent chain, find
            //          position of child.
            //          Repeat if needed
            //          Then point at pivot if any, or exit.
            //  Case 3: See that you're not in a leaf.
            //          Go down to the leftmost leaf of the
            //          right sub-tree.
            //          Start at first item. This one always
            //          exist.
            //  Case 4: same as case 1.
            //  Case 5: same as case 2.

            // If not a leaf, go inside the next children
            if (!_current.isLeaf)
            {
                // Case 3
                assert(_curItem + 1 < _current.numChildren);
                _current = _current.children[_curItem+1];
                while (!_current.isLeaf)
                    _current = _current.children[0];
                _curItem = 0;
            }
            else
            {
                _curItem += 1;
                if (_curItem >= _current.numKeys)
                {
                    while(true)
                    {
                        if (_current.parent is null)
                        {
                            // end of iteration
                            _current = null;
                            break;
                        }
                        else
                        {
                            // Find position of child in
                            // parent
                            int posParent = -2;
                            Node* c = _current;
                            Node* parent = _current.parent;

                            // Possibly there is a better
                            // way to do it with a stack
                            // somewhere. But that would
                            // require to know the maximum
                            // level.
                            // That, or change everything to
                            // be B+Tree.
                            size_t N = parent.numChildren();
                            for (int n = 0; n < N; ++n)
                            {
                                if (parent.children[n] == c)
                                {
                                    posParent = n;
                                    break;
                                }
                            }

                            // else tree invalid
                            // not sure why I took -2
                            assert(posParent != -2);

                            if (posParent < parent.numKeys)
                            {
                                // Point at pivot
                                _current = parent;
                                _curItem = posParent;
                                break;
                            }
                            else
                            {
                                // continue search upwards
                                // for a pivot
                                _current = parent;
                            }
                        }
                    }
                }
                else
                {
                    // Case 1, nothing to do.
                }
            }
        }

    private:
        // Next item returned by .front
        Node* _current;
        int _curItem;
    }
}

// <digression>
//
// A short note about B-tree "Knuth order" vs t/minDegree.
//
// t or "minimum degree" ensures an even number of children
// in full nodes.
//
//  .----------------+---------------+-------------------.
//  | minDegree max  | keys per node | children per node |
//  |----------------+---------------+-------------------|
//  |             2  |        1 to 3 |            2 to 4 |
//  |             3  |        2 to 5 |            3 to 6 |
//  |             4  |        3 to 7 |            4 to 8 |
//  +----------------+---------------+-------------------+
//
// However Knuth defines that as an "order" m, which can be
// an _odd_ number.
//
// In this case, the possible B-tree item bounds are:
//
//  .----------------+---------------+-------------------.
//  |      m         | keys per node | children per node |
//  |----------------+---------------+-------------------|
//  |             4  |        1 to 3 |            2 to 4 |
//  |             5  |        2 to 4 |            3 to 5 |
//  |             6  |        2 to 5 |            3 to 6 |
//  |             7  |        3 to 6 |            4 to 7 |
//  |             8  |        3 to 7 |            4 to 8 |
//  +----------------+---------------+-------------------+
//
// So, while things are similar for even m, they are
// different for odd m and some Internet example use m = 5.
// If we disallow non-even m, then it's impossible to
// It makes a difference in deletion, because two minimally
// filled nodes + a pivot can be merged together if m is
// even.
//
// Our implementation does NOT allow for odd m.
//
// </digression>

unittest // .init testing, basics
{
    // It should be possible to use most function of an
    // uninitialized BTree.
    // All except functions returning a range will work.
    BTree!(int, string) m;

    assert(m.length == 0);
    assert(m.empty);
    assert(!m.contains(7));
    m.insert(7, "lol");
    assert(m.contains(7));
    assert(m[7] == "lol");
    m.remove(7);
    assert(!m.contains(7));
    assert(m.length == 0);
    assert(m.empty);
    assert(m._root == null);
}

unittest // add and delete in reverse order
{
    enum int N = 10;
    for (int G = 0; G < 1; ++G)
    {
        BTree!(int, string) m;
        for (int k = 0; k < N; ++k)
        {
            m.insert(k, "l");
        }

        assert(m.length == N);
        for (int k = N-1; k >= 0; --k)
        {
            assert(1 == m.remove(k));
        }
        assert(m.length == 0);
        assert(m.empty);
    }
}

unittest // dupe keys
{
    BTree!(int, int, "a < b", true) m;
    enum KEY = 4;

    for (int n = 0; n < 32; ++n)
    {
        m.insert(KEY, 1 << n);
    }

    foreach(k; m.byKey)
        assert(k == KEY);

    int r = 0;
    for (int n = 0; n < 32; ++n)
    {
        int* p = KEY in m;
        assert(p);
        r |= *p;
        assert(m.remove(KEY) == 1);
    }
    assert(r == -1); // all were popped
}

unittest // "in" without initialization
{
    BTree!(int, int) m;
    void* p = 1 in m;
    assert(p is null);
}

unittest
{
    BTree!(int, int) m;
    m.insert(4, 5);
    m.insert(4, 9);
}
