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
 * Module to hold the deserializer base as well as the default `deserialize` implementations
 * for d's basic types (and some libphobos support). Also contains the default implementation
 * of `deserialize` for classes and structs.
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2024 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/mai-lapyst, Mai-Lapyst)
 */
module serde.de;

import std.traits :
    isFunction, hasUDA,
    isFloatingPoint, isScalarType, isSomeString,
    isAssociativeArray, KeyType, ValueType,
    isInstanceOf, TemplateArgsOf;
import std.container : SList, DList;
import std.typecons : StdTuple = Tuple;
import std.typecons : Nullable;

import serde.attrs;
import serde.error;

abstract class Deserializer {
    void read_basic(T)(ref T value) if (isScalarType!T);

    void read_ignore();

    interface SeqAccess {
        Nullable!ulong size_hint();
        bool read_element(T)(ref T element);
        bool end();
    }
    SeqAccess read_seq(T)();
    SeqAccess read_tuple(T)();

    interface MapAccess {
        bool read_key(K)(ref K key);
        bool read_value(V)(ref V value);
        void end();
    }
    MapAccess read_map(K, V)();
    MapAccess read_struct(T)(ref T value) if (is(T == struct) || is(T == class));
}

package (serde) struct IgnoreValue {}

/// Deserializes scalar types (bool, all integers, float, double, real, all char types)
pragma(inline) void deserialize(T, D : Deserializer)(ref T value, D de) if (isScalarType!T) {
    de.read_basic!T(value);
}

/// Deserializes an string
pragma(inline) void deserialize(T, D : Deserializer)(ref T str, D de) if (isSomeString!T) {
    de.read_string!T(str);
}

/// Ignores an value in deserialization
pragma(inline) void deserialize(D : Deserializer)(auto ref IgnoreValue v, D de) {
    de.read_ignore();
}

/// Deserializes an array
void deserialize(T, D : Deserializer)(ref T[] array, D de) if (!isSomeString!(T[])) {
    T[] new_array;
    auto access = de.read_seq!T();

    Nullable!ulong sz_hint = access.size_hint();
    if (!sz_hint.isNull) {
        new_array.reserve(sz_hint.get);
    }

    T entry;
    while (access.read_element(entry)) {
        new_array ~= entry;
    }
    access.end();

    array = new_array;
}

/// Deserializes an libphobos double-linked list
void deserialize(T, D : Deserializer)(ref DList!T list, D de) {
    DList!T new_list;
    auto access = de.read_seq!T();

    T entry;
    while (access.read_element(entry)) {
        new_list ~= entry;
    }
    access.end();

    list = new_list;
}

/// Deserializes an libphobos single-linked list
void deserialize(T, D : Deserializer)(ref SList!T list, D de) {
    SList!T new_list;
    auto access = de.read_seq!T();

    T entry;
    while (access.read_element(entry)) {
        new_list.insertAfter(new_list[], entry);
    }
    access.end();

    list = new_list;
}

/// Deserializes an associative array
void deserialize(AA, D : Deserializer)(ref AA aa, D de) if (isAssociativeArray!AA) {
    alias K = KeyType!AA;
    alias V = ValueType!AA;

    AA new_aa;
    scope(success) aa = new_aa;

    auto access = de.read_map!(K, V)();
    if (access is null) {
        // value was already completly parsed by read_struct.
        return;
    }

    K key;
    while (access.read_key(key)) {
        V val;
        access.read_value(val);
        new_aa[key] = val;
    }

    access.end();
}

/// Deserializes an libphobos tuple
void deserialize(T, D : Deserializer)(ref T tuple, D de) if (isInstanceOf!(StdTuple, T)) {
    alias Elements = T.Types;
    auto access = de.read_tuple!Elements();
    static foreach (i, E; Elements) {
        access.read_element!E(tuple[i]);
    }
    access.end();
}

private enum isSpecialStructOrClass(T) = (
    isInstanceOf!(StdTuple, T)
    || is(T == IgnoreValue)
    || isInstanceOf!(DList, T)
    || isInstanceOf!(SList, T)
);

void deserialize(T, D : Deserializer)(ref T value, D de)
if (
    (is(T == struct) || is(T == class))
    && !isSpecialStructOrClass!T
    && !__traits(compiles, T.deserialize)
    && !Serde.isUfcs!T
)
{
    import std.meta, std.traits;
    import ninox.std.traits;

    auto access = de.read_struct!T(value);
    if (access is null) {
        // value was already completly parsed by read_struct.
        return;
    }

    enum isFieldOfInterest(alias Field) = (
        !Serde.isSkipped!(Field.raw)
        && !Serde.isSkipped!(Field.type)
        && Field.compiles
    );
    alias fields = Filter!(isFieldOfInterest, GetFields!T);

    enum isSetter(alias Member) = (
        Member.compiles
        && (
            (is(Member.type == function) && Member.has_UDA!(Serde.Setter))
            || (isCallable!(Member.raw) && hasFunctionAttributes!(Member.raw, "@property"))
        )
    );
    template correctProp(alias Member)
    {
        static if(hasFunctionAttributes!(Member.raw, "@property")) {
            alias overloads = __traits(getOverloads, T, Member.name);
            alias setter = AliasSeq!();
            static foreach (overload; overloads) {
                static if (Parameters!overload.length == 1) {
                    setter = AliasSeq!(sgetter, overload);
                }
            }
            static assert(setter.length == 1, "Could not retrieve setter from overloads for @property " ~ Member.name);

            enum name = Member.name;
            alias type = Member.type;
            alias raw = setter[0];
        } else {
            alias correctProp = Member;
        }
    }
    alias setters = staticMap!(correctProp, Filter!(isSetter, GetDerivedMembers!T));

    template fieldToMember(alias Field) {
        enum name = Serde.getNameFromItem!(Field.raw, Field.name, false);
        enum index = Field.index;
        alias type = Field.type;
        enum code = "access.read_value(value." ~ Field.name ~ ");";
        alias aliases = Serde.getAliases!(Field.raw);
        enum optional = Serde.isOptional!(Field.raw);
    }
    template methodToMember(alias Member) {
        enum name = Serde.getNameFromItem!(Member.raw, Member.name, false);
        enum index = Member.index + fields.length;
        alias type = Parameters!(Member.type)[0];
        enum code = BuildImportCodeForType!type ~ " _val; access.read_value(_val); value." ~ Member.name ~ "(_val);";
        alias aliases = Serde.getAliases!(Member.raw);
        enum optional = Serde.isOptional!(Member.raw);
    }
    alias members = AliasSeq!(
        staticMap!(fieldToMember, fields),
        staticMap!(methodToMember, setters),
    );

    enum denyUnknownFields = Serde.shouldDenyUnknownFields!(T);

    struct FieldInfo {
        long index = -1;
        void opAssign(string name) {
            switch (name) {
                static foreach (m; members) {
                    case m.name: {
                        this.index = m.index;
                        return;
                    }
                    static foreach (a; m.aliases) {
                        case a: {
                            this.index = m.index;
                            return;
                        }
                    }
                }
                default: {
                    static if (denyUnknownFields) {
                        throw new UnknownFieldException(T.stringof, name);
                    }
                    else {
                        this.index = -1;
                    }
                }
            }
        }
        void opAssign(T)(T val) if (isNumeric!T && !isFloatingPoint!T) {
            static if (denyUnknownFields) {
                if (val < 0 || val > members.length) {
                    import std.conv : to;
                    throw new InvalidValueException(
                        "Unexpected field index " ~ val.to!string
                        ~ " for '" ~ T.stringof ~ "'; expected range: 0 - "
                        ~ (members.length-1).to!string
                    );
                }
            }
            this.index = val;
        }
    }

    import std.bitmanip : BitArray;
    enum _sourceLen = (members.length / 8) + 1;
    size_t[_sourceLen] _source;
    BitArray flags = BitArray(_source, members.length);

    enum memberName(alias m) = m.name;
    static immutable fieldNames = [ staticMap!(memberName, members) ];

    static foreach (m; members) {
        static if (m.optional) {
            flags[m.index] = true;
        }
    }

    FieldInfo fi;
    while (access.read_key(fi)) {
        Lsw: switch (fi.index) {
            static foreach (m; members) {
                case m.index: {
                    static if (!m.optional) {
                        if (flags[m.index]) {
                            throw new DuplicateFieldException(T.stringof, m.name);
                        }
                    }
                    mixin(m.code);
                    flags[m.index] = true;
                    break Lsw;
                }
            }
            default: {
                static if (denyUnknownFields) {
                    assert(0);
                } else {
                    auto ign = IgnoreValue();
                    access.read_value(ign);
                }
            }
        }
    }

    if (flags.count != members.length) {
        flags.flip();
        auto idx = flags.bitsSet.front;
        throw new MissingFieldException(T.stringof, fieldNames[idx]);
    }

    access.end();
}