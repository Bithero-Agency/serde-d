/*
 * serde.d:json - json format implementation for serde.d
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
 * Module to hold the serializer implementation for the json format.
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2024 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/mai-lapyst, Mai-Lapyst)
 */
module serde.json.ser;

import serde.ser;
import std.conv : to;
import std.traits : isSomeString, isScalarType;
import ninox.std.callable;

class JsonSerializer : Serializer {
    alias Sink = Callable!(void, const(char)[]);
    private {
        Sink sink;
        string indent = null;
        int _lvl = 0;
    }

    this(Sink.FnT sink) {
        this.sink = sink;
    }

    this(Sink.DgT sink) {
        this.sink = sink;
    }

    this(Sink sink) {
        this.sink = sink;
    }

    private void doIndent() {
        if (this.indent !is null) {
            write('\n');
            for (int l = 0; l < this._lvl; l++) {
                write(this.indent);
            }
        }
    }

    private void write(string s) {
        this.sink(s);
    }
    private void write(char c) {
        this.sink([c]);
    }

    override void write_bool(bool value) {
        write(value.to!string);
    }

    override void write_signed(long value, ubyte sz) {
        write(value.to!string);
    }

    override void write_unsigned(ulong value, ubyte sz) {
        write(value.to!string);
    }

    override void write_float(double value, ubyte sz) {
        write(value.to!string);
    }

    override void write_real(real value) {
        write(value.to!string);
    }

    override void write_char(dchar value) {
        this.write_string([value].to!string);
    }

    override void write_string(string str) {
        write('"');
        void appendData(const(ubyte)[] bytes) {
            this.sink(cast(const(char)[]) bytes);
        }
        import serde.common;
        backslashEscape!(appendData)(cast(ubyte[]) str);
        write('"');
    }

    override void write_raw(RawValue v) {
        write(cast(string) v.value);
    }

    override void write_enum(string name, ulong index) {
        write_string(name);
    }

    class Seq : Serializer.Seq {
        bool atStart = true;

        Serializer write_element() {
            if (!atStart) write(',');
            atStart = false;
            doIndent();
            return this.outer;
        }

        void end() {
            _lvl--;
            doIndent();
            write(']');
        }
    }
    override Seq start_seq() {
        write('[');
        _lvl++;
        return new Seq();
    }
    override Seq start_seq(ulong length) {
        write('[');
        _lvl++;
        return new Seq();
    }

    class Tuple : Serializer.Tuple {
        bool atStart = true;

        Serializer write_element() {
            if (!atStart) write(',');
            atStart = false;
            doIndent();
            return this.outer;
        }

        void end() {
            _lvl--;
            doIndent();
            write(']');
        }
    }
    override Tuple start_tuple() {
        write('[');
        _lvl++;
        return new Tuple();
    }

    class Map : Serializer.Map {
        bool atStart = true;
        void write_key(K)(K key) {
            if (!atStart) write(',');
            atStart = false;
            doIndent();
            key.serialize(this.outer);
        }
        void write_value(V)(V value) {
            write(':');
            if (indent !is null) write(' ');
            value.serialize(this.outer);
        }
        void end() {
            _lvl--;
            doIndent();
            write('}');
        }
    }
    override Map start_map() {
        write('{');
        _lvl++;
        return new Map();
    }
    override Map start_map(ulong length) {
        write('{');
        _lvl++;
        return new Map();
    }

    class Struct : Serializer.Struct {
        bool atStart = true;

        Serializer write_field(string name) {
            if (!atStart) write(',');
            atStart = false;
            doIndent();
            name.serialize(this.outer);
            write(':');
            if (indent !is null) write(' ');
            return this.outer;
        }

        void end() {
            _lvl--;
            doIndent();
            write('}');
        }
    }
    override Struct start_struct() {
        write('{');
        _lvl++;
        return new Struct();
    }
}

string toJson(T)(auto ref T t) {
    string outp = "";
    auto ser = new JsonSerializer(
        (const(char)[] chunk) { outp ~= chunk; }
    );
    t.serialize(ser);
    return outp;
}
void toJson(T)(auto ref T t, JsonSerializer.Sink sink) {
    auto ser = new JsonSerializer(sink);
    t.serialize(ser);
}
void toJson(T)(auto ref T t, JsonSerializer.Sink.FnT sink) {
    auto ser = new JsonSerializer(sink);
    t.serialize(ser);
}
void toJson(T)(auto ref T t, JsonSerializer.Sink.DgT sink) {
    auto ser = new JsonSerializer(sink);
    t.serialize(ser);
}

string toPrettyJson(T)(auto ref T t, string indent = "  ") {
    string outp = "";
    auto ser = new JsonSerializer(
        (const(char)[] chunk) { outp ~= chunk; }
    );
    ser.indent = indent;
    t.serialize(ser);
    return outp;
}
void toPrettyJson(T)(auto ref T t, JsonSerializer.Sink sink, string indent = "  ") {
    auto ser = new JsonSerializer(sink);
    ser.indent = indent;
    t.serialize(ser);
}
void toPrettyJson(T)(auto ref T t, JsonSerializer.Sink.FnT sink, string indent = "  ") {
    auto ser = new JsonSerializer(sink);
    ser.indent = indent;
    t.serialize(ser);
}
void toPrettyJson(T)(auto ref T t, JsonSerializer.Sink.DgT sink, string indent = "  ") {
    auto ser = new JsonSerializer(sink);
    ser.indent = indent;
    t.serialize(ser);
}
