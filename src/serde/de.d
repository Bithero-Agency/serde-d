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
import ninox.std.traits : hasDerivedMember;

import serde.attrs;
import serde.common;
import serde.error;
import serde.value;

interface Deserializer {
    /// Reads an boolean value.
    void read_bool(ref bool b);

    /// Reads an signed integer. `sz` specifies if for an byte(1), short(2), int(4) or long(8).
    void read_signed(ref long l, ubyte sz);

    /// Reads an unsigned integer. `sz` specifies if for an ubyte(1), ushort(2), uint(4) or ulong(8).
    void read_unsigned(ref ulong l, ubyte sz);

    /// Reads an floatingpoint number. `sz` specifies if for an float(4) or double(8).
    void read_float(ref double f, ubyte sz);

    /// Reads an real.
    void read_real(ref real r);

    /// Reads an character value.
    void read_char(ref dchar c);

    /// Reads an string.
    void read_string(ref string str);

    /// Reads an enum.
    /// The default enum deserializer expects to retrieve either a string or an integer value.
    void read_enum(ref AnyValue value);

    /// Ignores one value from the input stream.
    /// This is just an specialized form of `read_any()` where the value is not needed.
    void read_ignore();

    /// Reads any one value from the input.
    void read_any(ref AnyValue value);

    interface SeqAccess {
        /// Size hint of the sequence (or tuple).
        /// If an value is returned, the deserializing code can use this to reserve memory
        /// before starting to read elements.
        Nullable!ulong size_hint();

        /// Reads an element from the sequence / tuple.
        Deserializer read_element();

        /// Reads the end of a sequence / tuple.
        void end();
    }

    /// Starts reading a sequence.
    SeqAccess read_seq();

    /// Starts reading a tuple.
    SeqAccess read_tuple();

    interface MapAccess {
        /// Reads a key; returns `true` if successfull; `false` otherwise.
        /// If `true` was returned, this is immediately followed by `read_value` OR `ignore_value`.
        bool read_key(ref AnyValue value);

        /// Reads the value. Is immediately after `read_key`.
        /// The returned Deserializer MUST be used to read the final value.
        Deserializer read_value();

        /// Ignores the value. Is immediately after `read_key`.
        void ignore_value();

        /// Reads the end of an map / struct.
        void end();
    }

    /// Starts reading a map.
    MapAccess read_map();

    /// Starts reading a struct/class.
    /// If you want to set the class to `null`, parse the entire value here and return `null`.
    MapAccess read_struct();
}

/// Used as marker to ignore an value from the input
struct IgnoreValue {}

/// Deserializes scalar types (bool, all integers, float, double, real, all char types)
pragma(inline) void deserialize(T)(ref T value, Deserializer de) if (isScalarType!T && !is(T == enum)) {
    import std.traits : isSomeChar, isUnsigned;
    static if (__traits(isFloating, T)) {
        double d; de.read_float(d, T.sizeof); value = cast(T) d;
    }
    else static if (is(T == real)) {
        de.read_real(value);
    }
    else static if (is(T == bool)) {
        de.read_bool(value);
    }
    else static if (isSomeChar!T) {
        dchar ch; de.read_char(ch); value = cast(T) ch;
    }
    else static if (isUnsigned!T) {
        ulong l; de.read_unsigned(l, T.sizeof); value = cast(T) l;
    }
    else {
        long l; de.read_signed(l, T.sizeof); value = cast(T) l;
    }
}

/// Deserializes an string
pragma(inline) void deserialize(T)(ref T str, Deserializer de) if (isSomeString!T && !is(T == enum)) {
    static if (is(T == string)) {
        de.read_string(str);
    }
    else {
        string raw;
        de.read_string(raw);
        import std.conv : to;
        str = raw.to!T;
    }
}

/// Ignores an value in deserialization
pragma(inline) void deserialize()(auto ref IgnoreValue v, Deserializer de) {
    de.read_ignore();
}

/// Deserializes an enum
pragma(inline) void deserialize(T)(ref T value, Deserializer de) if(is(T == enum)) {
    // Enums are either stored as:
    //  - string with their name
    //  - index into the enum

    AnyValue val;
    de.read_enum(val);
    if (auto str = val.peek!string) {
        value = getEnumValueByKey!T(*str);
        return;
    }

    auto ty = val.type();
    if (
        ty == typeid(ubyte)
        || ty == typeid(ushort)
        || ty == typeid(uint)
        || ty == typeid(ulong)
    ) {
        value = getEnumValueByIndex!T(val.get!ulong);
    }
    else if (
        ty == typeid(byte)
        || ty == typeid(short)
        || ty == typeid(int)
        || ty == typeid(long)
    ) {
        value = getEnumValueByIndex!T(val.get!long);
    }
    else {
        throw new SerdeException(
            "Can deserialize enums only from strings or integer types, got: " ~ ty.toString
        );
    }
}

/// Deserializes an array
void deserialize(T)(ref T[] array, Deserializer de) if (!isSomeString!(T[])) {
    T[] new_array;
    auto access = de.read_seq();

    Nullable!ulong sz_hint = access.size_hint();
    if (!sz_hint.isNull) {
        new_array.reserve(sz_hint.get);
    }

    Deserializer elem_de;
    while ((elem_de = access.read_element()) !is null) {
        T entry;
        entry.deserialize(elem_de);
        new_array ~= entry;
    }
    access.end();

    array = new_array;
}

/// Deserializes an libphobos double-linked list
void deserialize(T)(ref DList!T list, Deserializer de) {
    DList!T new_list;
    auto access = de.read_seq();

    Deserializer elem_de;
    while ((elem_de = access.read_element()) !is null) {
        T entry;
        entry.deserialize(elem_de);
        new_list ~= entry;
    }
    access.end();

    list = new_list;
}

/// Deserializes an libphobos single-linked list
void deserialize(T)(ref SList!T list, Deserializer de) {
    SList!T new_list;
    auto access = de.read_seq();

    Deserializer elem_de;
    while ((elem_de = access.read_element()) !is null) {
        T entry;
        entry.deserialize(elem_de);
        new_list.insertAfter(new_list[], entry);
    }
    access.end();

    list = new_list;
}

/// Deserializes an associative array
void deserialize(AA)(ref AA aa, Deserializer de) if (isAssociativeArray!AA && !is(AA == enum)) {
    alias K = KeyType!AA;
    alias V = ValueType!AA;

    AA new_aa;
    scope(success) aa = new_aa;

    auto access = de.read_map();
    if (access is null) {
        // value was already completly parsed by read_struct.
        return;
    }

    AnyValue rawKey, rawVal;
    while (access.read_key(rawKey)) {
        K key = rawKey.get!K;
        V val; val.deserialize(access.read_value());
        new_aa[key] = val;
    }

    access.end();
}

/// Deserializes an libphobos tuple
void deserialize(T)(ref T tuple, Deserializer de) if (isInstanceOf!(StdTuple, T)) {
    alias Elements = T.Types;
    auto access = de.read_tuple();
    static foreach (i, E; Elements) {
        {
            auto elem_de = access.read_element();
            assert(elem_de !is null);
            tuple[i].deserialize(elem_de);
        }
    }
    access.end();
}

/// Deserializes an "any" value;
/// This can be either an instance of libphobos `std.variant.VariantN`,
/// or alternatively, one of `ninox.std.variant.Variant`.
void deserialize(T)(ref T var, Deserializer de) if (isAnyValue!T) {
    de.read_any(var);
}

private enum isSpecialStructOrClass(T) = (
    isInstanceOf!(StdTuple, T)
    || is(T == IgnoreValue)
    || isInstanceOf!(DList, T)
    || isInstanceOf!(SList, T)
    || isAnyValue!T
);

void deserialize(T)(ref T value, Deserializer de)
if (
    (is(T == struct) || is(T == class))
    && !is(T == enum)
    && !isSpecialStructOrClass!T
    && hasDerivedMember!(T, "deserializeInstance")
) {
    T.deserializeInstance(value, de);
}

void deserialize(T)(ref T value, Deserializer de)
if (
    (is(T == struct) || is(T == class))
    && !is(T == enum)
    && !isSpecialStructOrClass!T
    && !__traits(compiles, T.deserialize)
    && !hasDerivedMember!(T, "deserializeInstance")
    && !Serde.isUfcs!T
)
{
    import std.meta, std.traits;
    import ninox.std.traits;

    auto access = de.read_struct();
    if (access is null) {
        // value was already completly parsed by read_struct.
        static if (is(T == class)) {
            value = null;
        }
        return;
    }

    enum isFieldOfInterest(alias Field) = (
        !Serde.isSkipped!(Field.raw)
        && !Serde.isSkipped!(Field.type)
        && Field.compiles
    );
    alias fields = Filter!(isFieldOfInterest, GetFields!T);

    enum hasPropertySetter(alias overload) = (
        hasFunctionAttributes!(overload, "@property")
        && Parameters!overload.length == 1
    );
    enum isSetter(alias Member) = (
        Member.compiles
        && !Serde.isSkipped!(Member.raw)
        && (
            (isFunction!(Member.raw) && Member.has_UDA!(Serde.Setter))
            || (
                isCallable!(Member.raw)
                && hasFunctionAttributes!(Member.raw, "@property")
                && Filter!(hasPropertySetter, Member.overloads).length == 1
            )
        )
    );
    template correctProp(alias Member)
    {
        static if(hasFunctionAttributes!(Member.raw, "@property")) {
            alias overloads = __traits(getOverloads, T, Member.name);
            alias setter = AliasSeq!();
            static foreach (overload; overloads) {
                static if (Parameters!overload.length == 1) {
                    setter = AliasSeq!(setter, overload);
                }
            }

            static if (setter.length != 1) {
                static assert(0, "Could not retrieve setter from overloads for @property " ~ Member.name);
            }
            else {
                enum name = Member.name;
                alias type = Member.type;
                alias raw = setter[0];
                enum index = Member.index;
            }
        } else {
            alias correctProp = Member;
        }
    }
    alias setters = staticMap!(correctProp, Filter!(isSetter, GetDerivedMembers!T));

    template fieldToMember(size_t i, alias Field)
    {
        enum name = Serde.getNameFromItem!(Field.raw, Field.name, false);
        enum index = i;
        alias type = Field.type;
        enum code = "value." ~ Field.name ~ ".deserialize(val_de);";
        alias aliases = Serde.getAliases!(Field.raw);
        enum optional = Serde.isOptional!(Field.raw);
    }
    template methodToMember(size_t i, alias Member)
    {
        enum name = Serde.getNameFromItem!(Member.raw, Member.name, false);
        enum index = i + fields.length;
        alias type = Parameters!(Member.type)[0];
        enum code = BuildImportCodeForType!type ~ " __val; __val.deserialize(val_de); value." ~ Member.name ~ "(__val);";
        alias aliases = Serde.getAliases!(Member.raw);
        enum optional = Serde.isOptional!(Member.raw);
    }
    alias members = AliasSeq!(
        staticMapWithIndex!(fieldToMember, fields),
        staticMapWithIndex!(methodToMember, setters),
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
    static immutable string[] fieldNames = [ staticMap!(memberName, members) ];

    static foreach (m; members) {
        static if (m.optional) {
            flags[m.index] = true;
        }
    }

    static if (is(T == class)) {
        if (value is null) {
            value = new T();
        }
    }

    FieldInfo fi;
    AnyValue key;
    while (access.read_key(key)) {
        if (key.peek!long !is null) {
            fi = key.get!long;
        }
        else if (key.peek!string !is null) {
            fi = key.get!string;
        }
        else {
            throw new InvalidValueException("Unexpected " ~ key.type.toString ~ ", expected field identifier");
        }

        Lsw: switch (fi.index) {
            static foreach (m; members) {
                case m.index: {
                    static if (!m.optional) {
                        if (flags[m.index]) {
                            throw new DuplicateFieldException(T.stringof, m.name);
                        }
                    }
                    auto val_de = access.read_value();
                    mixin(m.code);
                    flags[m.index] = true;
                    break Lsw;
                }
            }
            default: {
                static if (denyUnknownFields) {
                    assert(0);
                } else {
                    access.ignore_value();
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

/*unittest {
    class A {
    @(Serde.Optional):

        @property void my_prop(int i) {}

        @(Serde.Setter)
        void my_setter(int i, int j) {}
    }

    class FooSerializer : Deserializer {
        override void read_ignore() {}
        class MapAccess : Deserializer.MapAccess {
            bool read_key(K)(ref K key) { return false; }
            void read_value(V)(ref V val) {}
            void end() {}
        }
        override MapAccess read_struct() { return new MapAccess(); }
    }

    A a; deserialize(a, new FooSerializer());
}*/
