/**
 * A simple @nogc map, that also happens to be quite dumb.
 * 
 * It is used for X11 mapping of window id's to instances,
 * if you need something like this for anything more serious, replace!
 * Or look into EMSI's containers.
 * 
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Richard (Rikki) Andrew Cattermole
 */
module dplug.core.dumbnogcmap;

/// A dumb slow @nogc map implementation. You probably don't want to use this...
/// No seriously, its probably worse than O(n)!
struct DumbSlowNoGCMap(K, V)
{
    import dplug.core.nogc;
    import std.typecons : Nullable;

    private
    {
        Nullable!K[] keys_;
        V[] values_;
    }

@nogc:

    @disable
    this(this);

    ~this()
    {
        freeSlice(keys_);
        freeSlice(values_);
    }

    V opIndex(K key)
    {
        foreach(i, ref k; keys_)
        {
            if (!k.isNull && k == key)
                return values_[i];
        }

        return V.init;
    }

    void opIndexAssign(V value, K key)
    {
        if (keys_.length == 0)
        {
            keys_ = mallocSlice!(Nullable!K)(8);
            values_ = mallocSlice!V(8);
            keys_[0] = key;
            values_[0] = value;

            keys_[1 .. $] = Nullable!K.init;

            return;
        }
        else
        {
            foreach(i, ref k; keys_)
            {
                if (!k.isNull && k == key)
                {
                    values_[i] = value;
                    return;
                }
            }

            foreach(i, ref k; keys_)
            {
                if (k.isNull)
                {
                    k = key;
                    values_[i] = value;
                    return;
                }
            }
        }

        Nullable!K[] newKeys = mallocSlice!(Nullable!K)(keys_.length+8);
        V[] newValues = mallocSlice!V(values_.length+8);
        newKeys[0 .. $-8] = keys_;
        newValues[0 .. $-8] = values_;

        newKeys[$-7] = key;
        newKeys[$-6 .. $] = Nullable!K.init;
        newValues[$-7] = value;

        freeSlice(keys_);
        freeSlice(values_);

        keys_ = newKeys;
        values_ = newValues;
    }

    void remove(K key)
    {
        foreach(i, ref k; keys_)
        {
            if (!k.isNull && k == key)
            {
                k.nullify;
                values_[i] = V.init;
                return;
            }
        }
    }

    bool haveAValue() {
        foreach(i, ref k; keys_)
        {
            if (!k.isNull)
            {
                return true;
            }
        }

        return false;
    }
}