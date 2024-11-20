/*
 * serde.d - serialization and deserialization framework
 * Copyright (C) 2024 Mai-Lapyst
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 * 
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

/**
 * Module to hold the "any" value by either using libphobos `std.variant.VariantN`,
 * or `ninox.std.variant.Variant`, if both ninox.d-std:variant AND the version
 * "SerdeUseNinoxVariant" is set.
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2024 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/mai-lapyst, Mai-Lapyst)
 */
module serde.value;

import std.variant : VariantN;
import std.traits : isInstanceOf;

enum isStdVariant(alias T) = isInstanceOf!(VariantN, T);

version (SerdeUseNinoxVariant) {
    version (Have_ninox_d_std_variant) {
        pragma(msg, "Using ninox.d-std:variant to provide AnyValue");

        public import ninox.std.variant : NinoxVariant = Variant;

        /// Default type to provide an "any" value.
        alias AnyValue = NinoxVariant;

        /// Check if any given type `T` is an valid "any" type.
        enum isAnyValue(alias T) = isStdVariant!T || is(T == NinoxVariant);
    }
    else {
        static assert(0, "Cannot use ninox.d-std:variant without having it installed");
    }
}
else {
    pragma(msg, "Using libphobos std.variant to provide AnyValue");

    import std.variant : StdVariant = Variant;

    /// Default type to provide an "any" value.
    alias AnyValue = StdVariant;

    /// Check if any given type `T` is an valid "any" type.
    enum isAnyValue(alias T) = isStdVariant!T;
}

import serde.de;

class AnyValueDeserializer : Deserializer {
    AnyValue val;
    this(ref AnyValue val) {
        this.val = val;
    }

    override void read_bool(ref bool b) {
        b = this.val.get!bool;
    }
    override void read_signed(ref long l, ubyte sz) {
        l = this.val.get!long;
    }
    override void read_unsigned(ref ulong l, ubyte sz) {
        l = this.val.get!ulong;
    }
    override void read_float(ref double f, ubyte sz) {
        f = this.val.get!double;
    }
    override void read_real(ref real r) {
        r = this.val.get!real;
    }
    override void read_char(ref dchar c) {
        c = this.val.get!dchar;
    }

    override void read_string(ref string str) {
        str = this.val.get!string;
    }

    override void read_ignore() {}

    override void read_any(ref AnyValue value) {
        value = this.val;
    }

    class SeqAccess : Deserializer.SeqAccess {
        import std.typecons : Nullable;

        AnyValue[] seq;
        this(AnyValue[] seq) {
            this.seq = seq;
        }

        Nullable!ulong size_hint() { return Nullable!ulong(); }

        Deserializer read_element() {
            if (seq.length > 0) {
                auto val = seq[0];
                seq = seq[1..$];
                return new AnyValueDeserializer(val);
            }
            return null;
        }

        void end() {}
    }

    override Deserializer.SeqAccess read_seq() {
        auto seq = this.val.get!(AnyValue[]);
        return new SeqAccess(seq);
    }

    override Deserializer.SeqAccess read_tuple() {
        auto seq = this.val.get!(AnyValue[]);
        return new SeqAccess(seq);
    }

    class MapAccess : Deserializer.MapAccess {
        AnyMap map;
        this(ref AnyMap map) {
            this.map = map;
        }

        bool read_key(ref AnyValue key) {
            if (map.entries.length > 0) {
                key = map.entries[0].key;
                return true;
            }
            return false;
        }

        Deserializer read_value() {
            if (map.entries.length > 0) {
                auto de = new AnyValueDeserializer(map.entries[0].val);
                map.entries = map.entries[1..$];
                return de;
            }
            return null;
        }

        void ignore_value() {
            if (map.entries.length > 0) {
                map.entries = map.entries[1..$];
            }
        }

        void end() {}
    }

    override Deserializer.MapAccess read_map() {
        auto map = this.val.get!(AnyMap);
        return new MapAccess(map);
    }

    override Deserializer.MapAccess read_struct() {
        auto map = this.val.get!(AnyMap);
        return new MapAccess(map);
    }
}

struct AnyMap {
    static struct Entry {
        AnyValue key;
        AnyValue val;
    }
    Entry[] entries;

    this(K, V)(V[K] map) {
        foreach (ref k, v; map) {
            static if (is(K == AnyValue) && is(V == AnyValue)) {
                entries ~= Entry(k, v);
            }
            else static if (is(K == AnyValue)) {
                entries ~= Entry(k, AnyValue(v));
            }
            else static if (is(V == AnyValue)) {
                entries ~= Entry(AnyValue(k), v);
            }
            else {
                entries ~= Entry(AnyValue(k), AnyValue(v));
            }
        }
    }

    private Entry* findEntry(ref AnyValue key) {
        foreach (ref e; entries) {
            if (e.key == key) {
                return &e;
            }
        }
        return null;
    }

    ref auto opIndex(I)(I index) {
        static if (is(I == AnyValue)) {
            auto e = findEntry(index);
        } else {
            AnyValue idx = index;
            auto e = findEntry(idx);
        }
        if (e is null) {
            throw new Exception("Out of bounds!");
        }
        return e.val;
    }

    auto opIndexAssign(T, I)(T value, I index) {
        static if (is(I == AnyValue)) {
            auto e = findEntry(index);
        } else {
            AnyValue idx = index;
            auto e = findEntry(idx);
        }
        if (e !is null) {
            e.val = value;
        } else {
            static if (is(I == AnyValue) && is(T == AnyValue)) {
                entries ~= Entry(index, value);
            }
            else static if (is(I == AnyValue)) {
                entries ~= Entry(index, AnyValue(value));
            }
            else static if (is(T == AnyValue)) {
                entries ~= Entry(idx, value);
            }
            else {
                entries ~= Entry(idx, AnyValue(value));
            }
        }
        return value;
    }

    auto opBinary(string op : "in", R)(const R index) {
        static if (is(I == AnyValue)) {
            auto e = findEntry(index);
        } else {
            AnyValue idx = index;
            auto e = findEntry(idx);
        }
        if (e is null) return null;
        return &(e.val);
    }

    auto opBinaryRight(string op : "in", R)(const R index) {
        static if (is(I == AnyValue)) {
            auto e = findEntry(index);
        } else {
            AnyValue idx = index;
            auto e = findEntry(idx);
        }
        if (e is null) return null;
        return &(e.val);
    }
}

unittest {
    AnyMap map;
    map[AnyValue("abc")] = 12;

    auto k = AnyValue("abc");
    assert(map.findEntry(k) !is null);

    assert(map["abc"] == 12);

    assert(("abc" in map) !is null);
    assert(*("abc" in map) == 12);

    assert("def" !in map);
}
