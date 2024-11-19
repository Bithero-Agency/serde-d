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
 * Module to hold the deserializer implementation for the json format.
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2024 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/mai-lapyst, Mai-Lapyst)
 */
module serde.json.de;

import serde.de;
import serde.common;
import serde.value;

import std.traits : isFloatingPoint, isScalarType, isSomeString, isSomeChar;
import std.string : startsWith;
import std.typecons : Nullable, nullable;
import std.range : popFrontExactly;

import core.internal.util.math : min;

class JsonDeserializer : Deserializer {
    ReadBuffer buffer;
    bool strict = false;

    this(string inp) {
        this.buffer = ReadBuffer(cast(char[]) inp);
    }
    this(ReadBuffer.Source.FnT source) {
        this.buffer = ReadBuffer(source);
    }
    this(ReadBuffer.Source.DgT source) {
        this.buffer = ReadBuffer(source);
    }
    this(ReadBuffer.Source source) {
        this.buffer = ReadBuffer(source);
    }

    pragma(inline)
    private void skip_ws() {
        this.buffer.skipWhitespace;
    }

    pragma(inline)
    private auto peek_char() {
        return this.buffer.front;
    }

    pragma(inline)
    private auto next_char() {
        auto ch = peek_char();
        this.buffer.popFront;
        return ch;
    }

    pragma(inline)
    private void consume_char(char c, string msg) {
        if (next_char != c) {
            throw new Exception(msg);
        }
    }

    override void read_bool(ref bool value) {
        skip_ws;
        if (this.buffer.startsWith("true")) {
            this.buffer.popFrontExactly(4);
            value = true;
        }
        else if (this.buffer.startsWith("false")) {
            this.buffer.popFrontExactly(5);
            value = false;
        }
        else {
            throw new Exception("Expected boolean");
        }
    }

    override void read_float(ref double value, ubyte sz) {
        import std.conv : parse;
        value = parse!double(this.buffer);
    }
    override void read_real(ref real value) {
        import std.conv : parse;
        value = parse!real(this.buffer);
    }

    private void read_basic(T)(ref T value) if (isScalarType!T && !is(T == bool) && !isFloatingPoint!T) {
        skip_ws;

        import std.traits : isUnsigned;
        static if (!isUnsigned!T) {
            bool shouldNegate = false;
            if (peek_char == '-') {
                next_char;
                shouldNegate = true;
            }
        }
        switch(peek_char) {
            case '0': .. case '9': {
                static if (!isUnsigned!T) {
                    long v;
                } else {
                    ulong v;
                }
                v = next_char - '0';
                Lloop: while(!this.buffer.empty) {
                    auto ch = this.buffer.front;
                    switch (ch) {
                        case '0': .. case '9': {
                            v *= 10;
                            v += ch - '0';
                            this.buffer.popFront;
                            continue;
                        }
                        default: {
                            break Lloop;
                        }
                    }
                }
                static if (!isUnsigned!T) {
                    v = shouldNegate ? v*-1 : v;
                }
                if (v > T.max) {
                    throw new Exception("Cannot fit integer");
                }
                value = cast(T) v;
                return;
            }
            default: {
                static if (isSomeChar!T) {
                    string str;
                    this.read_string(str);
                    if (str.length < 1) {
                        throw new Exception("Expected number or non-empty string");
                    }
                    import std.utf : decode;
                    size_t i = 0;
                    value = decode(str, i);
                    return;
                }
                throw new Exception("Expected integer");
            }
        }
    }

    override void read_signed(ref long l, ubyte sz) {
        this.read_basic!long(l);
    }
    override void read_unsigned(ref ulong l, ubyte sz) {
        this.read_basic!ulong(l);
    }
    override void read_char(ref dchar c) {
        this.read_basic!dchar(c);
    }

    unittest {
        import std.conv;
        static immutable testCases = [
            "\"a\"": 'a',
            "\"💙\"": '💙',
            "97": 'a',
        ];
        foreach (inp, r; testCases) {
            dchar ch = 0;
            try {
                auto de = new JsonDeserializer(inp);
                de.read_char(ch);
                assert(de.buffer.empty, "Failed parsing '" ~ inp ~ "'; still data left in buffer");
            }
            catch (Exception e) {
                assert(0, "Failed parsing '" ~ inp ~ "'; got Exception: " ~ e.message());
            }
            assert(ch == r, "Failed parsing '" ~ inp ~ "'; expected " ~ r.to!string ~ " but got " ~ ch.to!string);
        }
    }

    override void read_string(ref string str) {
        skip_ws;
        consume_char('"', "Expected string start");
        str = backslashUnescape(this.buffer, '"');
        consume_char('"', "Expected string end");
    }

    private void read_null() {
        if (this.buffer.startsWith("null")) {
            this.buffer.popFrontExactly(4);
        } else {
            throw new Exception("Expected null");
        }
    }

    override void read_ignore() {
        skip_ws;
        switch (peek_char) {
            case 'n': { read_null(); break; }
            case 't': case 'f': {
                bool b; read_bool(b); break;
            }
            case '"': {
                string str; read_string(str); break;
            }
            case '0': .. case '9':
            case '-': {
                double d; this.read_float(d, double.sizeof); break;
            }
            case '[': case '{': {
                char[] stack;
                dchar c;
                while (true) {
                    c = next_char;
                    if (c == '{') stack ~= '}';
                    else if (c == '[') stack ~= ']';
                    else if (c == '}' || c == ']') {
                        if (c == stack[$-1]) stack = stack[0..$-1];
                        else throw new Exception("Syntax error");
                        if (stack.length <= 0) break;
                    }
                }
                break;
            }
            default: {
                throw new Exception("Syntax error");
            }
        }
    }

    override void read_any(ref AnyValue value) {
        skip_ws;
        switch (this.buffer.front) {
            case 'n': {
                read_null();
                value = null;
                break;
            }
            case 't': case 'f': {
                bool b;
                read_bool(b);
                value = b;
                break;
            }
            case '"': {
                string str;
                read_string(str);
                value = str;
                break;
            }
            case '0': .. case '9':
            case '-':
            {
                double d;
                this.read_float(d, double.sizeof);
                if (cast(long) d == d) {
                    // is a non-floating point number
                    auto l = cast(long) d;
                    if (l >= byte.min && l <= byte.max) {
                        value = cast(byte) l;
                    } else if (l >= short.min && l <= short.max) {
                        value = cast(short) l;
                    } else if (l >= int.min && l <= int.max) {
                        value = cast(int) l;
                    } else {
                        value = l;
                    }
                }
                else {
                    value = d;
                }
                break;
            }
            case '[': {
                AnyValue[] array;
                array.deserialize(this);
                value = array;
                break;
            }
            case '{': {
                AnyValue[string] map;
                map.deserialize(this);
                value = AnyMap(map);
                break;
            }
            default: {
                throw new Exception("Syntax error");
            }
        }
    }

    /// Test read_any
    unittest {
        import std.variant : Variant;
        import std.conv : to;
        auto testCases = [
            "true": Variant(true),
            "false": Variant(false),
            "123": Variant(cast(long) 123),
            "-123": Variant(cast(long) -123),
            "12.3": Variant(cast(double) 12.3),
            "\"abc\"": Variant("abc"),
            "null": Variant(null),
            "[1, 2]": Variant([Variant(1), Variant(2)]),
            "{\"a\": 12}": Variant([ "a": Variant(12) ]),
        ];
        foreach (inp, expected; testCases) {
            Variant var;
            try {
                (new JsonDeserializer(inp)).read_any(var);
            } catch (Exception e) {
                assert(0, "Failed to parse '" ~ inp ~ "': got Exception: " ~ e.message());
            }
            assert(var == expected, "Failed to parse '" ~ inp ~ "': expected " ~ expected.to!string ~ " but got " ~ var.to!string);
        }
    }

    void read_enum(T)(ref T value) if (is(T == enum)) {
        string val;
        read_string(val);
        value = getEnumValueByKey!T(val);
    }

    class SeqAccess : Deserializer.SeqAccess {
        bool atStart = true;

        Nullable!ulong size_hint() { return Nullable!ulong(); }

        Deserializer read_element() {
            skip_ws;
            if (peek_char == ']') return null;
            if (!atStart && next_char != ',') throw new Exception("Expected array comma");
            atStart = false;
            skip_ws;
            if (!strict && peek_char == ']') return null;
            return this.outer;
        }

        void end() {
            skip_ws;
            consume_char(']', "Expected array end");
        }
    }

    override SeqAccess read_seq() {
        skip_ws;
        consume_char('[', "Expected array start");
        return new SeqAccess();
    }

    override SeqAccess read_tuple() {
        skip_ws;
        consume_char('[', "Expected array start");
        return new SeqAccess();
    }

    class MapAccess : Deserializer.MapAccess {
        bool atStart = true;

        override bool read_key(ref AnyValue key) {
            skip_ws;
            if (peek_char == '}') return false;
            if (!atStart && next_char != ',') throw new Exception("Expected map comma");
            atStart = false;
            skip_ws;
            if (!strict && peek_char == '}') return false;
            string s; this.outer.read_string(s); key = s;
            return true;
        }

        override Deserializer read_value() {
            skip_ws;
            this.outer.consume_char(':', "Expected map colon");
            skip_ws;
            return this.outer;
        }

        override void ignore_value() {
            skip_ws;
            this.outer.consume_char(':', "Expected map colon");
            skip_ws;
            this.outer.read_ignore();
        }

        void end() {
            skip_ws;
            consume_char('}', "Expected map end");
        }
    }

    override MapAccess read_map() {
        skip_ws;
        this.consume_char('{', "Expected map start");
        return new MapAccess();
    }

    unittest {
        assert(`{"aa":12}`.parseJson!(int[string]) == ["aa":12]);
    }

    override MapAccess read_struct() {
        skip_ws;
        static if (is(T == class)) {
            if (this.buffer.startsWith("null")) {
                this.buffer.popFrontExactly(4);
                return null;
            }
        }
        this.consume_char('{', "Expected map start");
        return new MapAccess();
    }
}

void fromJson(T)(auto ref T value, string inp) {
    auto de = new JsonDeserializer(inp);
    value.deserialize(de);
}
void fromJson(T)(auto ref T value, ReadBuffer.Source source) {
    auto de = new JsonDeserializer(source);
    value.deserialize(de);
}
void fromJson(T)(auto ref T value, ReadBuffer.Source.FnT source) {
    auto de = new JsonDeserializer(source);
    value.deserialize(de);
}
void fromJson(T)(auto ref T value, ReadBuffer.Source.DgT source) {
    auto de = new JsonDeserializer(source);
    value.deserialize(de);
}

void fromJsonStrict(T)(auto ref T value, string inp) {
    auto de = new JsonDeserializer(inp);
    de.strict = true;
    value.deserialize(de);
}
void fromJsonStrict(T)(auto ref T value, ReadBuffer.Source source) {
    auto de = new JsonDeserializer(source);
    de.strict = true;
    value.deserialize(de);
}
void fromJsonStrict(T)(auto ref T value, ReadBuffer.Source.FnT source) {
    auto de = new JsonDeserializer(source);
    de.strict = true;
    value.deserialize(de);
}
void fromJsonStrict(T)(auto ref T value, ReadBuffer.Source.DgT source) {
    auto de = new JsonDeserializer(source);
    de.strict = true;
    value.deserialize(de);
}

pragma(inline) T parseJson(T)(string inp) {
    T val = T.init;
    val.fromJson(inp);
    return val;
}
pragma(inline) T parseJsonStrict(T)(string inp) {
    T val = T.init;
    val.fromJsonStrict(inp);
    return val;
}
