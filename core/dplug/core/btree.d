/**
* Vanilla B-Tree implementation.
* Note that this is an implementation detail of dplug.core.map and not part of
* the public dplug:core API.
*
* Copyright: Copyright Guillaume Piolat 2024.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
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
    An implementation of a vanilla B-Tree.

    The API should looks closely like the builtin associative arrays.
    O(lg(n)) insertion, removal, and search time.
    This `BTree` is designed to operate even without initialization through
    `makeBTree`.

    Note: the keys don't need opEquals, but !(a < b) && !(b > a) should 
          imply that a == b

    Reference: 
        http://staff.ustc.edu.cn/~csli/graduate/algorithms/book6/chap19.htm
        https://en.wikipedia.org/wiki/B-tree
*/
// TODO: map over range of keys
struct BTree(K,                            // type of the keys
             V,                            // type of the values
             alias less = "a < b",         // must be strict inequality
             
             bool allowDuplicates = false, // dupe keys allowed or not

             bool duplicateKeyIsUB = false) // user guarantees no duplicates
                                            // for faster inserts 
                                            // (works when allowDuplicates is false)
{
public:
nothrow:
@nogc:

    /// Called "t" or "minimum degree" in litterature, can never be < 2.
    /// Make it lower (eg: 2) to test tree algorithms.
    /// See <digression> below to see why this is not B-Tree "order".
    enum minDegree = 16; // PERF: tune this vs size of K and V

    // Every node must have >= minKeysPerNode and <= maxKeysPerNode.
    // The root node is allowed to have < minKeysPerNode (but not zero).
    enum int minKeys     =     minDegree - 1; 
    enum int maxKeys     = 2 * minDegree - 1;
    enum int minChildren =     minDegree;
    enum int maxChildren = 2 * minDegree;

    debug(btree) invariant()
    {
        checkInvariant();
    }

    // Not copyable.
    @disable this(this);

    /**
        Constructor.
    */
    this(int dummy)
    {
        // It does nothing, because T.init is valid.
    }

    /**
        Destructor. All nodes are cleared.
    */
    ~this()
    {
        if (_root)
        {
            _root.reclaimMemory(); // PERF: find a way to deallocate all at once
            _root = null;
        }
    }    

    /**
        Number of items in the B-Tree.
        Returns: Number of elements.
    */
    size_t length() const
    {
        return _count;
    }

    /**
        Is this B-Tree empty?
        Returns: `true` if zero elements.
    */
    bool empty() const 
    {
        return _count == 0;
    }

    /**
        Insert an element in the container. 

        Returns: `true` if the insertion took place.
                 If duplicates are supported, return true.

        WARNING: inserting duplicate keys when duplicates are not supported
        is Undefined Behaviour. Use `contains()` to avoid that case.
    */
    bool insert(K key, V value) 
    {
        lazyInitialize();

        // Runtime check to prevent accidental dupe keys.
        static if (!allowDuplicates)
        {
            static if (duplicateKeyIsUB)
            {
                // Detect dupes, but in -release it will be Undefined Behaviour
                assert(findKeyValue(_root, key) is null);
            }
            else
            {
                // Always detect dupes, this slows down insertion by a lot
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
        Return forward range of values, over all elements.
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
        Return forward range of keys, over all elements.
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
        Return forward range of a struct that has .key and .value.
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
        Erases an element from the tree, if found.
        Returns: Number of elements erased (for now: 0 or 1 only).
    */
    size_t remove(K key)
    {
        if (_root is null)
            return 0;

        int keyIndex;
        Node* node = findNode(_root, key, keyIndex);
        if (node is null)
            return 0; // not found

        _count -= 1;

        // Reference: https://www.youtube.com/watch?app=desktop&v=0NvlyJDfk1M
        if (node.isLeaf)
        {
            // First, remove key, then eventually rebalance.
            deleteKeyValueAtIndexAndShift(node, keyIndex);
            rebalanceAfterDeletion(node);
        }
        else
        {
            // Exchange key with either highest of the smaller key in leaf,
            // or largest of the highest keys
            //          . value .
            //         /         \
            //        /           \
            //       /             \
            // left subtree      right subtree

            // But I'm not sure why people tout this solution.
            // Here we simply always get to the rightmost leaf node of left 
            // subtree. It seems it's always possible indeed, and it's not
            // faster to look at the other sub-tree.
            Node* leafNode = node.children[keyIndex];
            while (!leafNode.isLeaf)
                leafNode = leafNode.children[leafNode.numKeys];
            assert(leafNode);

            // Remove key from leaf node, put it instead of target.
            node.kv[keyIndex] = leafNode.kv[leafNode.numKeys-1];
            leafNode.numKeys -= 1;

            // and then rebalance
            rebalanceAfterDeletion(leafNode);
        }
        
        return 1;
    }

    /**
        `in` operator. Check to see if the given element exists in the
        container.
        In case of duplicate keys, it returns one of those, unspecified order.
    */
    inout(V)* opBinaryRight(string op)(K key) inout if (op == "in")
    {
        if (_root is null)
            return null;
        inout(KeyValue)* kv = findKeyValue(_root, key);
        if (!kv) return null;
        return &kv.value;
    }

    /**
        Index the B-Tree by key.
        Returns: A reference to the value corresponding to this key.
                 In case of duplicate keys, it returns one of the values,
                 in unspecified order.
    */
    ref inout(V) opIndex(K key) inout
    {
        inout(V)* p = key in this;
        return *p;
    }

    /**
        Search for an element.
        Returns: `true` if the element is present.
    */
    bool contains(K key) const
    {
        if (_root is null)
            return false;
        return findKeyValue(_root, key) !is null;
    }

private:

    alias _less = binaryFun!less;

    Node* _root;
    size_t _count;

    void checkInvariant() const
    {
        int count = 0;
        if (_root)
        {
            assert(_count > 0);
            checkNodeInvariant(_root, null, count);
        }
        else
        {
            assert(_count == 0); // No elements <=> null _root node.
        }
        assert(count == _count);
    }

    // null if not found
    inout(KeyValue)* findKeyValue(inout(Node)* x, K key) inout
    {
        int index;
        inout(Node)* node = findNode(x, key, index);
        if (node is null)
            return null;
        else 
            return &(node.kv[index]);
    }

    // Return containing node + index of value in store, or null of nothing found.
    inout(Node)* findNode(inout(Node)* x, K key, out int index) inout
    {
        int i = 0;
        while (i < x.numKeys && _less(x.kv[i].key, key))
            i += 1;

        // Like in Phobos Red Black tree, !less(a,b) && !less(b,a) means equality.

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
        // create new child, that will take half the keyvalues and children of 
        // the full y node
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
        // * new child is inserted right of its older sibling
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

    // Take one node that is exactly below capacity, and reinstate 
    // the invariant by merging nodes and exchanging with neighbours.
    // Is called on nodes that might be missing exactly one item.
    void rebalanceAfterDeletion(Node* node)
    {
        if (node.parent is null)   // is this the tree _root?
        {
            assert(_root is node);
            
            if (_root.numKeys == 0)
            {        
                if (_root.isLeaf)  // no more items in tree
                {
                    destroyFree(_root);
                    _root = null;
                }
                else               // tree is reduced by one level
                {
                    Node* oldRoot = _root;
                    _root = oldRoot.children[0];
                    _root.parent = null;
                    oldRoot.numKeys = -1;
                    oldRoot.children[0] = null; // so that it is not destroyed
                    destroyFree(oldRoot);       // <- here
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
        
        if (childIndex != 0)                      // has left sibling?
            left = parent.children[childIndex-1];
        
        if (childIndex + 1 < parent.numChildren)  // has right sibling?
            right = parent.children[childIndex+1];

        assert(left || right);                    // one of those must exists

        if (left && left.numKeys > minKeys)
        {
            // Take largest key from left sibling, it becomes the new pivot in 
            // parent. Old pivot erase our key (and if non-leaf, gets the left 
            // sibling right subtree + the node one child).
            assert(left.isLeaf == node.isLeaf);
            KeyValue largest = left.kv[left.numKeys - 1];
            Node* rightMostChild = left.children[left.numKeys];
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
                node.children[0] = rightMostChild;
                rightMostChild.parent = node;
            }
            node.numKeys = minKeys;
        }
        else if (right && right.numKeys > minKeys)
        {
            // take smallest key from right sibling, it becomes the new pivot in parent
            // old pivot erase our key
            assert(right.isLeaf == node.isLeaf);
            KeyValue smallest = right.kv[0];
            Node* leftMostChild = right.children[0];

            // Delete first key (and first child, if any) of right sibling.
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

    // merge children nth and nth+1, which must both have min amount of keys
    // it makes one node with max amount of keys
    void mergeChild(Node* parent, int nth)
    {
        Node* left = parent.children[nth];
        Node* right = parent.children[nth+1];
        KeyValue pivot = parent.kv[nth];
        assert(left.isLeaf == right.isLeaf);

        // One key is missing already
        assert(left.numKeys + right.numKeys == 2*minKeys - 1);

        left.kv[left.numKeys] = pivot;

        for (int n = 0; n < right.numKeys; ++n)
        {
            left.kv[left.numKeys + 1 + n] = right.kv[n];
        }
        if (!left.isLeaf)
        {
            for (int n = 0; n < right.numKeys+1; ++n)
            {
                left.children[left.numKeys + 1 + n] = right.children[n];
                assert(right.children[n].parent == right);
                left.children[left.numKeys + 1 + n].parent = left;
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

        // in case the parent has too few elements
        rebalanceAfterDeletion(parent);

        destroyFree(right);
    }

    // internal use, delete a kv and shift remaining kv
    void deleteKeyValueAtIndexAndShift(Node* node, int index)
    {
        node.numKeys -= 1;
        for (int n = index; n < node.numKeys; ++n)
        {
            node.kv[n] = node.kv[n+1];
        }
    }

    void checkNodeInvariant(const(Node)* node, const(Node)* parent, ref int count) const
    {
        // Each node of the tree except the root must contain at least minDegree − 1 keys 
        // (and hence must have at least `minDegree` children if it is not a leaf).        
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
                checkNodeInvariant(node.children[n], node, count);
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

            // Check key orderings with children. All keys of child must be inside parent range.
            for (int n = 0; n < node.numKeys; ++n)
            {
                const(K) k = node.kv[n].key;

                // All key of left children must be smaller, right must be larger.
                const(Node)* left = node.children[n];
                const(Node)* right = node.children[n+1];

                for (int m = 0; m < left.numKeys; ++m)
                {
                    static if (allowDuplicates)
                    {
                        assert(! _less(k, left.kv[m].key));
                    }
                    else
                    {
                        assert(_less(left.kv[m].key, k));
                    }
                }

                for (int m = 0; m < right.numKeys; ++m)
                {
                    static if (allowDuplicates)
                    {
                        assert(!_less(right.kv[m].key, k));
                    }
                    else
                    {
                        assert(_less(k, right.kv[m].key));
                    }
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
        printf("Tree has %zu elements\n", _count);
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

        // This node stored numKeys keys, and numKeys+1 children.
        int numKeys;

        // Keys and values together.
        KeyValue[maxKeys] kv;

        // (borrowed) Parent node. Can be null, for the root.
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
            printf("   * leaf = %s\n", isLeaf ? "yes".ptr: "no".ptr);
            printf("   * numKeys = %d\n", numKeys);

            if (numKeys > 0)
            {
                for (int v = 0; v < numKeys; ++v)
                {
                    static if (is(V == string))
                        printf("        - Contains key %d and value %s\n", 
                               kv[v].key, kv[v].value.ptr);
                    else
                        printf("        - Contains key %d\n", kv[v].key);
                }
            }
            if (!isLeaf)
            {
                for (int v = 0; v < numKeys+1; ++v)
                {
                    printf("        - Point to child %p\n", children[v]);
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
            _current = cast(Node*)(tree._root); // const_cast here
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
                return _current.kv[_currentItem].key;
            static if (type == RangeType.value)
                return _current.kv[_currentItem].value; 
            static if (type == RangeType.keyValue)
                return _current.kv[_currentItem];
        }

        void popFront()
        {
            // If not a leaf, go inside the next children
            if (!_current.isLeaf)
            {
                _current = _current.children[_currentItem];
                _currentItem = 0;
            }
            else
            {
                _currentItem++;
                if (_currentItem >= _current.numKeys)
                {
                search_next:
                    Node* child = _current;
                    Node* parent = _current.parent;

                    if (parent)
                    {
                        _currentItem = -2;
                        
                        // Find index of child.
                        // Possibly there is a better way to do it with a stack somewhere
                        // but that would require to know the maximum level.
                        // That, or change everything to be B+Tree.
                        for (int n = 0; n < parent.numChildren(); ++n)
                        {
                            if (parent.children[n] == child)
                            {
                                _currentItem = n + 1;
                                if (_currentItem >= parent.numKeys)
                                {
                                    // Go up one level.
                                    _current = parent;
                                    goto search_next;
                                }
                            }
                        }
                        assert(_currentItem != -2);
                    }
                    else
                    {
                        // finished iterating the _root, no more items
                        _current = null;
                    }
                }
            }
        }

    private:
        // Next item returned by .front
        Node* _current;
        int _currentItem;
    }
}

// <digression>
//
// A short note about B-tree "Knuth order" vs t/minDegree.
//
// t or "minimum degree" ensures an even number of children in full nodes.
//
//  .----------------+---------------+-------------------.
//  | minDegree max  | keys per node | children per node |
//  |----------------+---------------+-------------------|
//  |             2  |        1 to 3 |            2 to 4 |
//  |             3  |        2 to 5 |            3 to 6 |
//  |             4  |        3 to 7 |            4 to 8 |
//  +----------------+---------------+-------------------+
//
// However Knuth defines that as an "order" m, which can be _odd_.
// https://stackoverflow.com/questions/42705423/can-an-m-way-b-tree-have-m-odd
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
// So, while things are similar for even m, they are different 
// for odd m and some Internet example use m = 5.
// If we disallow non-even m, then it's impossible to 
// It makes a difference in deletion, because two minimally 
// filled nodes + a pivot can be merged together if m is even.
//
// Our implementation does NOT allow for odd m.
//
// </digression>

unittest // .init testing, basics
{
    // It should be possible to use most function of an uninitialized Map
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
