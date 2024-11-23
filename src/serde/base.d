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
 * Module to holds an base serializer/deserializer,
 * where all methods throw an exception.
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2024 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/mai-lapyst, Mai-Lapyst)
 */
module serde.base;

import serde.error;
import serde.de;
import serde.ser;
import serde.value;

import std.conv : to;

abstract class BaseSerializer : Serializer {
    this() {}

    void write_bool(bool b) {
        throw new SerdeException("Unimplemented write_bool in " ~ this.classinfo.to!string);
    }
    void write_signed(long l, ubyte sz) {
        throw new SerdeException("Unimplemented write_signed in " ~ this.classinfo.to!string);
    }
    void write_unsigned(ulong l, ubyte sz) {
        throw new SerdeException("Unimplemented write_unsigned in " ~ this.classinfo.to!string);
    }
    void write_float(double f, ubyte sz) {
        throw new SerdeException("Unimplemented write_float in " ~ this.classinfo.to!string);
    }
    void write_real(real r) {
        throw new SerdeException("Unimplemented write_real in " ~ this.classinfo.to!string);
    }
    void write_char(dchar c) {
        throw new SerdeException("Unimplemented write_char in " ~ this.classinfo.to!string);
    }

    void write_string(string str) {
        throw new SerdeException("Unimplemented write_string in " ~ this.classinfo.to!string);
    }

    void write_raw(RawValue v) {
        throw new SerdeException("Unimplemented write_raw in " ~ this.classinfo.to!string);
    }

    void write_enum(string name, ulong index) {
        throw new SerdeException("Unimplemented write_enum in " ~ this.classinfo.to!string);
    }

    Seq start_seq() {
        throw new SerdeException("Unimplemented start_seq in " ~ this.classinfo.to!string);
    }
    Seq start_seq(ulong length) {
        throw new SerdeException("Unimplemented start_seq with length in " ~ this.classinfo.to!string);
    }

    Tuple start_tuple() {
        throw new SerdeException("Unimplemented start_tuple in " ~ this.classinfo.to!string);
    }

    Map start_map() {
        throw new SerdeException("Unimplemented start_map in " ~ this.classinfo.to!string);
    }
    Map start_map(ulong length) {
        throw new SerdeException("Unimplemented start_map with length in " ~ this.classinfo.to!string);
    }

    Struct start_struct() {
        throw new SerdeException("Unimplemented start_struct in " ~ this.classinfo.to!string);
    }
}

abstract class BaseDeserializer : Deserializer {
    void read_bool(ref bool b) {
        throw new SerdeException("Unimplemented write_bool in " ~ this.classinfo.to!string);
    }
    void read_signed(ref long l, ubyte sz) {
        throw new SerdeException("Unimplemented read_signed in " ~ this.classinfo.to!string);
    }
    void read_unsigned(ref ulong l, ubyte sz) {
        throw new SerdeException("Unimplemented read_unsigned in " ~ this.classinfo.to!string);
    }
    void read_float(ref double f, ubyte sz) {
        throw new SerdeException("Unimplemented read_float in " ~ this.classinfo.to!string);
    }
    void read_real(ref real r) {
        throw new SerdeException("Unimplemented read_real in " ~ this.classinfo.to!string);
    }
    void read_char(ref dchar c) {
        throw new SerdeException("Unimplemented read_char in " ~ this.classinfo.to!string);
    }

    void read_string(ref string str) {
        throw new SerdeException("Unimplemented read_string in " ~ this.classinfo.to!string);
    }

    void read_enum(ref AnyValue value) {
        throw new SerdeException("Unimplemented read_enum in " ~ this.classinfo.to!string);
    }

    void read_ignore() {
        throw new SerdeException("Unimplemented read_ignore in " ~ this.classinfo.to!string);
    }

    void read_any(ref AnyValue value) {
        throw new SerdeException("Unimplemented read_any in " ~ this.classinfo.to!string);
    }

    SeqAccess read_seq() {
        throw new SerdeException("Unimplemented read_seq in " ~ this.classinfo.to!string);
    }
    SeqAccess read_tuple() {
        throw new SerdeException("Unimplemented read_tuple in " ~ this.classinfo.to!string);
    }

    MapAccess read_map() {
        throw new SerdeException("Unimplemented read_map in " ~ this.classinfo.to!string);
    }

    MapAccess read_struct() {
        throw new SerdeException("Unimplemented read_struct in " ~ this.classinfo.to!string);
    }
}
