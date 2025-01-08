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
 * Module to hold the serializer base as well as the default `serialize` implementations
 * for d's basic types (and some libphobos support). Also contains the default implementation
 * of `serialize` for classes and structs.
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2024 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/mai-lapyst, Mai-Lapyst)
 */
module serde.ser;

import std.traits :
    isFunction, hasUDA,
    isScalarType, isSomeString,
    isAssociativeArray, KeyType, ValueType,
    isInstanceOf, TemplateArgsOf;
import std.conv : to;
import std.container : SList, DList;
import std.range.primitives : isInputRange, ElementType, hasLength;
import std.typecons : StdTuple = Tuple;
import std.typecons : Nullable, NullableRef;
import ninox.std.traits : hasDerivedMember;

import serde.attrs;
import serde.common;

interface Serializer {

    /// Writes an boolean value.
    void write_bool(bool b);

    /// Writes an signed integer. `sz` specifies byte(1), short(2), int(4) or long(8).
    void write_signed(long l, ubyte sz);

    /// Writes an unsigned integer. `sz` specifies ubyte(1), ushort(2), uint(4) or ulong(8).
    void write_unsigned(ulong l, ubyte sz);

    /// Writes an floating-point number. `sz` specifies float(4) or double(8).
    void write_float(double f, ubyte sz);

    /// Writes an real value.
    void write_real(real r);

    /// Writes an character value.
    void write_char(dchar c);

    /// Writes an "string" value. (Not an enum!).
    void write_string(string str);

    /// Writes an raw value; internally used to support the `Serde.Raw` annotation.
    void write_raw(RawValue v);

    /// Optionals are choice-types which either hold a value (some), or nothing (none).
    interface Optional {
        /// Writes the some
        Serializer write_some();

        /// Writes the none
        void write_none();

        /// Ends the optional.
        void end();
    }

    /// Starts an optional.
    Optional start_optional();

    /// Writes an enum value.
    void write_enum(string name, ulong index);

    /// Sequences are arbitary length chains of elements.
    interface Seq {
        /// Writes an element of the sequence.
        Serializer write_element();

        /// Closes the sequence.
        void end();
    }

    /// Starts an sequence of unknown length.
    Seq start_seq();

    /// Starts an sequence of known length.
    Seq start_seq(ulong length);

    /// Tuples are fixed sized chains of elements where each element can be a different type...
    interface Tuple {
        /// Writes an element of the tuple.
        Serializer write_element();

        /// Closes the tuple.
        void end();
    }

    /// Starts an tuple.
    Tuple start_tuple();

    /// Maps are key-value pairs
    interface Map {
        /// Writes the key of the pair. Is immediately followed by `write_value`.
        Serializer write_key();

        /// Writes the value of the pair. Is immediatly after `write_key`.
        Serializer write_value();

        /// Closes the map.
        void end();
    }

    /// Starts an map with unknown length.
    Map start_map();

    /// Starts an map with an known length.
    Map start_map(ulong length);

    /// Structs are... well structs
    interface Struct {
        /// Writes an field.
        Serializer write_field(string name);

        /// Closes the struct.
        void end();
    }

    /// Starts an struct.
    Struct start_struct();
}

package (serde) struct RawValue {
    const(char)[] value;
}

/// Serializes scalar types (bool, all integers, float, double, real, all char types)
pragma(inline) void serialize(T)(T value, Serializer ser) if (isScalarType!T && !is(T == enum)) {
    import std.traits : isSomeChar, isUnsigned;
    static if (__traits(isFloating, T)) {
        ser.write_float(value, T.sizeof);
    }
    else static if (is(T == real)) {
        ser.write_real(value);
    }
    else static if (is(T == bool)) {
        ser.write_bool(value);
    }
    else static if (isSomeChar!T) {
        ser.write_char(cast(dchar) value);
    }
    else static if (isUnsigned!T) {
        ser.write_unsigned(cast(ulong) value, T.sizeof);
    }
    else {
        ser.write_signed(cast(long) value, T.sizeof);
    }
}

/// Serializes an string
pragma(inline) void serialize(T)(auto ref T str, Serializer ser) if (isSomeString!T && !is(T == enum)) {
    static if (is(T == string)) {
        ser.write_string(str);
    } else {
        ser.write_string(str.to!string);
    }
}

/// Serializes an string raw
pragma(inline) void serialize()(ref RawValue value, Serializer ser) {
    ser.write_raw(value);
}

/// Serializes an enum
pragma(inline) void serialize(T)(T value, Serializer ser) if (is(T == enum)) {
    auto index = getEnumKeyIndex(value);
    ser.write_enum(value.getEnumKeyName(index), index);
}

/// Serializes an array
void serialize(T)(T[] array, Serializer ser) if (!isSomeString!(T[])) {
    auto s = ser.start_seq(array.length);
    foreach (ref el; array) {
        el.serialize(s.write_element());
    }
    s.end();
}

/// Serializes an libphobos double-linked list
void serialize(T)(DList!T list, Serializer ser) {
    auto s = ser.start_seq();
    foreach (ref el; list) {
        el.serialize(s.write_element());
    }
    s.end();
}
/// Serializes an libphobos single-linked list
void serialize(T)(SList!T list, Serializer ser) {
    auto s = ser.start_seq();
    foreach (ref el; list) {
        el.serialize(s.write_element());
    }
    s.end();
}

/// Serializes an input range;
/// if the range also has an length attribute, it is taken into account.
void serialize(R)(auto ref R range, Serializer ser) if (isInputRange!R && !isSomeString!R && !isInstanceOf!(Nullable, R)) {
    alias T = ElementType!R;
    static if (hasLength!R) {
        auto s = ser.start_seq(range.length);
    } else {
        auto s = ser.start_seq();
    }
    foreach (ref el; range) {
        el.serialize(s.write_element());
    }
    s.end();
}

/// Serializes an associative array
void serialize(AA)(auto ref AA aa, Serializer ser) if (isAssociativeArray!AA && !is(AA == enum)) {
    alias K = KeyType!AA;
    alias V = ValueType!AA;
    auto m = ser.start_map(aa.length);
    foreach (ref k, ref v; aa) {
        k.serialize(m.write_key());
        v.serialize(m.write_value());
    }
    m.end();
}

/// Serializes an libphobos tuple
void serialize(T)(auto ref T tuple, Serializer ser) if (isInstanceOf!(StdTuple, T)) {
    alias Elements = T.Types;
    auto t = ser.start_tuple();
    static foreach (i, E; Elements) {
        tuple[i].serialize(t.write_element());
    }
    t.end();
}

/// Serializes an libphobos optional / `Nullable!T` & `NullableRef!T`
void serialize(T)(auto ref T nullable, Serializer ser) if (isInstanceOf!(Nullable, T) || isInstanceOf!(NullableRef, T)) {
    auto opt = ser.start_optional();
    if (nullable.isNull()) {
        opt.write_none();
    } else {
        nullable.get().serialize(opt.write_some());
    }
    opt.end();
}

private enum isSpecialStructOrClass(T) = (
    isInstanceOf!(StdTuple, T)
    || isInputRange!T
    || is(T == RawValue)
    || isInstanceOf!(DList, T)
    || isInstanceOf!(SList, T)
    || isInstanceOf!(NullableRef, T)
);

void serialize(T)(auto ref T value, Serializer der)
if (
    (is(T == struct) || is(T == class) || is(T == interface))
    && !is(T == enum)
    && !isSpecialStructOrClass!T
    && hasDerivedMember!(T, "serializeInstance")
) {
    T.serializeInstance(value, der);
}

/// Serializes structs and classes that are not already handled in special cases of `serialize`,
/// have not already an member named `serialize` and are not marked with `Serde.UseUfcs`.
void serialize(T)(auto ref T val, Serializer ser)
if (
    (is(T == struct) || is(T == class))
    && !is(T == enum)
    && !isSpecialStructOrClass!T
    && !__traits(compiles, T.serialize)
    && !hasDerivedMember!(T, "serializeInstance")
    && !Serde.isUfcs!T
) {
    auto s = ser.start_struct();
    val.serializeInto(s);
    s.end();
}

/// Serializes structs and classes that are not already handled in special cases of `serialize`,
/// have not already an member named `serialize` and are not marked with `Serde.UseUfcs`.
/// 
/// Special "into" variant, that uses an existing Serializer.Struct instead of an Serializer.
void serializeInto(T)(auto ref T val, Serializer.Struct s)
if (
    (is(T == struct) || is(T == class))
    && !is(T == enum)
    && !isSpecialStructOrClass!T
    && !__traits(compiles, T.serialize)
    && !hasDerivedMember!(T, "serializeInstance")
    && !Serde.isUfcs!T
) {
    import std.meta, std.traits;
    import ninox.std.traits;

    enum isFieldOfInterest(alias Field) = (
        !Serde.isSkipped!(Field.raw)
        && !Serde.isSkipped!(Field.type)
        && Field.compiles
    );
    alias fields = Filter!(isFieldOfInterest, GetFields!T);
    static foreach (f; fields) {
        {
            auto fser = s.write_field(Serde.getNameFromItem!(f.raw, f.name, true));
            static if (Serde.isRaw!(f.raw)) {
                static assert(isSomeString!(f.type), "@Serde.Raw can only be applied to fields with a string type.");
                RawValue(mixin("val." ~ f.name)).serialize(fser);
            }
            else {
                mixin("val." ~ f.name).serialize(fser);
            }
        }
    }

    enum hasPropertyGetter(alias overload) = (
        hasFunctionAttributes!(overload, "@property")
        && !is(ReturnType!overload == void)
        && Parameters!overload.length == 0
    );
    enum isGetter(alias Member) = (
        Member.compiles
        && !Serde.isSkipped!(Member.raw)
        && (
            (isFunction!(Member.raw) && Member.has_UDA!(Serde.Getter))
            || (
                isCallable!(Member.raw)
                && hasFunctionAttributes!(Member.raw, "@property")
                && Filter!(hasPropertyGetter, Member.overloads).length == 1
            )
        )
    );
    template correctProp(alias Member)
    {
        static if(hasFunctionAttributes!(Member.raw, "@property")) {
            alias overloads = __traits(getOverloads, T, Member.name);
            alias getter = AliasSeq!();
            static foreach (overload; overloads) {
                static if (!is(ReturnType!overload == void) && Parameters!overload.length == 0) {
                    getter = AliasSeq!(getter, overload);
                }
            }

            static if (getter.length != 1) {
                static assert(0, "Could not retrieve getter from overloads for @property " ~ Member.name);
            }
            else {
                enum name = Member.name;
                alias type = Member.type;
                alias raw = getter[0];
            }
        } else {
            alias correctProp = Member;
        }
    }
    alias getters = staticMap!(correctProp, Filter!(isGetter, GetDerivedMembers!T));
    static foreach (m; getters) {
        {
            auto fser = s.write_field(Serde.getNameFromItem!(m.raw, m.name, true));
            static if (Serde.isRaw!(m.raw)) {
                static assert(isSomeString!(ReturnType!(m.type)), "@Serde.Raw can only be applied to fields with a string type.");
                RawValue(mixin("val." ~ m.name ~ "()")).serialize(fser);
            }
            else {
                mixin("val." ~ m.name ~ "()").serialize(fser);
            }
        }
    }

}
