/*
 * serde.d:yaml - yaml format implementation for serde.d
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
 * Module to hold the serializer implementation for the yaml format.
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2024 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/mai-lapyst, Mai-Lapyst)
 */
module serde.yaml.ser;

import serde.ser;
import std.conv : to;
import std.traits : isSomeString, isScalarType;
import ninox.std.callable;

private bool isPrintable(char[] c) {
    return
        ((c[0] == 0x0A)         /* . == #x0A */
            || (c[0] >= 0x20       /* #x20 <= . <= #x7E */
                && c[0] <= 0x7E)
            || (c[0] == 0xC2       /* #0xA0 <= . <= #xD7FF */
                && c[1] >= 0xA0)
            || (c[0] > 0xC2
                && c[0] < 0xED)
            || (c[0] == 0xED
                && c[1] < 0xA0)
            || (c[0] == 0xEE)
            || (c[0] == 0xEF      /* #xE000 <= . <= #xFFFD */
                && !(c[1] == 0xBB        /* && . != #xFEFF */
                    && c[2] == 0xBF)
                && !(c[1] == 0xBF
                    && (c[2] == 0xBE
                        || c[2] == 0xBF))))
    ;
}

private bool isPrintableStr(char[] s) {
    while (s.length > 2) {
        if (!isPrintable(s)) return false;
        s = s[1..$];
    }
    if (s.length > 1) {
        if (!isPrintable([ s[0], s[1], 0 ])) return false;
    }
    if (s.length > 0) {
        if (!isPrintable([ s[0], 0, 0 ])) return false;
    }
    return true;
}

class YamlSerializer : Serializer {
    alias Sink = Callable!(void, const(char)[]);
    private {
        Sink sink;
        string _indent = "  ";
        int _lvl = -1;
        bool _printsKey = false;
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

    private void indent() {
        for (int l = 0; l < _lvl; l++)
            sink(this._indent);
    }

    void write_basic(T)(T value) if (isScalarType!T) {
        static if (is(T == char) || is(T == wchar) || is(T == dchar)) {
            sink("'" ~ value.to!string ~ "'");
        } else {
            sink(value.to!string);
        }
    }

    void write_string(T)(scope T str) if (isSomeString!T) {
        import std.string : empty, indexOf, lineSplitter;
        import std.typecons : Yes;

        if (str.empty) {
            if (_printsKey) sink("\"\"");
            return;
        }

        auto hasLinebreaks = str.indexOf('\n') >= 0;

        if (
            (_printsKey && hasLinebreaks)
            || !isPrintableStr(str.to!(char[]))
        ) {
            sink("\"");
            void appendData(const(ubyte)[] bytes) {
                this.sink(cast(const(char)[]) bytes);
            }
            import serde.common;
            backslashEscape!(appendData)(cast(ubyte[]) str);
            sink("\"");
            return;
        }

        if (!hasLinebreaks) {
            sink(str.to!string);
            return;
        }

        sink("|");
        if (str[$-1] == '\n') {
            if (str[$-2] == '\n') sink("+");
            str = str[0..$-1];
        }
        else {
            sink("-");
        }
        sink("\n");
        foreach (ref line; str.lineSplitter!(Yes.keepTerminator)) {
            indent();
            sink("  ");
            sink(line);
        }
    }

    override void write_raw(RawValue v) {
        sink(cast(string) v.value);
    }

    class Seq : Serializer.Seq {
        bool atStart = true;
        void write_element(T)(T e) {
            if (!atStart) sink("\n");
            atStart = false;
            indent();
            sink("- ");
            e.serialize(this.outer);
        }
        void end() {
            _lvl--;
        }
    }
    Seq start_seq(T)() {
        if (_lvl >= 0) sink("\n");
        _lvl++;
        return new Seq();
    }
    Seq start_seq(T)(ulong length) {
        if (_lvl >= 0) sink("\n");
        _lvl++;
        return new Seq();
    }

    class Tuple : Serializer.Tuple {
        bool atStart = true;
        void write_element(E)(E e) {
            if (!atStart) sink(",");
            atStart = false;
            e.serialize(this.outer);
        }
        void end() {
            sink("]");
        }
    }
    Tuple start_tuple(Elements...)() {
        sink("[");
        return new Tuple();
    }

    class Map : Serializer.Map {
        bool atStart = true;
        void write_key(K)(K key) {
            if (!atStart) sink("\n");
            atStart = false;
            indent();
            {
                _printsKey = true;
                scope(exit) _printsKey = false;
                key.serialize(this.outer);
            }
        }
        void write_value(V)(V value) {
            sink(": ");
            value.serialize(this.outer);
        }
        void end() {
            _lvl--;
        }
    }
    Map start_map(K, V)() {
        if (_lvl >= 0) sink("\n");
        _lvl++;
        return new Map();
    }
    Map start_map(K, V)(ulong length) {
        if (_lvl >= 0) sink("\n");
        _lvl++;
        return new Map();
    }

    class Struct : Serializer.Struct {
        bool atStart = true;
        void write_field(T)(string name, T value) {
            if (!atStart) sink("\n");
            atStart = false;
            indent();
            {
                _printsKey = true;
                scope(exit) _printsKey = false;
                name.serialize(this.outer);
            }
            sink(": ");
            value.serialize(this.outer);
        }
        void end() {
            _lvl--;
        }
    }
    override Struct start_struct() {
        if (_lvl >= 0) sink("\n");
        _lvl++;
        return new Struct();
    }

}

string toYaml(T)(auto ref T t) {
    string outp = "";
    auto ser = new YamlSerializer(
        (const(char)[] chunk) { outp ~= chunk; }
    );
    t.serialize(ser);
    return outp;
}
void toYaml(T)(auto ref T t, YamlSerializer.Sink sink) {
    auto ser = new YamlSerializer(sink);
    t.serialize(ser);
}
void toYaml(T)(auto ref T t, YamlSerializer.Sink.FnT sink) {
    auto ser = new YamlSerializer(sink);
    t.serialize(ser);
}
void toYaml(T)(auto ref T t, YamlSerializer.Sink.DgT sink) {
    auto ser = new YamlSerializer(sink);
    t.serialize(ser);
}
