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

    override Deserializer.SeqAccess read_seq() {
        throw new Exception("NO SEQ");
    }

    override Deserializer.SeqAccess read_tuple() {
        throw new Exception("NO TUP");
    }

    override Deserializer.MapAccess read_map() {
        throw new Exception("NO MAP");
    }

    override Deserializer.MapAccess read_struct() {
        throw new Exception("NO STRUCT");
    }
}
