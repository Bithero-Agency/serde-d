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
 * Module to hold the deserializer implementation for the yaml format.
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2024 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/mai-lapyst, Mai-Lapyst)
 */
module serde.yaml.de;

import serde.de;
import serde.common;
import serde.yaml.error;

import std.traits : isScalarType, isFloatingPoint, isSomeString;
import std.conv : to, parse, ConvException;
import std.string : toLower, startsWith;
import std.math.traits : isNaN;
import std.range : popFrontExactly;
import std.algorithm : countUntil;

private auto isNsDecDigit(dchar ch) => ch >= '0' && ch <= '9';
private auto isNsHexDigit(dchar ch) => ch.isNsDecDigit || (ch >= 'A' && ch <= 'F') || (ch >= 'a' && ch <= 'f');
private auto isNsAsciiLetter(dchar ch) => (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z');
private auto isNsWordChar(dchar ch) => ch.isNsDecDigit || ch.isNsAsciiLetter || ch == '-';

private auto isFlowIndicator(dchar ch) => ch == ',' || ch == '[' || ch == ']' || ch == '{' || ch == '}';

private auto isIndicator(dchar ch) {
    switch (ch) {
        case '-':
        case '?':
        case ':':
        case ',':
        case '[':
        case ']':
        case '{':
        case '}':
        case '#':
        case '&':
        case '*':
        case '!':
        case '|':
        case '>':
        case '\'':
        case '"':
        case '%':
        case '@': case '`':
            return true;
        default:
            return false;
    }
}

private enum Context {
    /// Inside block context
    BlockIn,
    /// Outside block context
    BlockOut,
    /// Inside block key context
    BlockKey,
    /// Inside flow context
    FlowIn,
    /// Outside flow context
    FlowOut,
    /// Inside flow key context
    FlowKey,
}

pragma(inline) private auto isBreak(dchar ch) => ch == '\r' || ch == '\n';
pragma(inline) private auto isWhite(dchar ch) => ch == ' ' || ch == '\t';
pragma(inline) private auto isNsChar(dchar ch) => !ch.isBreak && !ch.isWhite;

pragma(inline) private auto isNsPlainSafeOut(dchar ch) => ch.isNsChar;
pragma(inline) private auto isNsPlainSafeIn(dchar ch) => ch.isNsChar && !ch.isFlowIndicator;
private auto isNsPlainSafe(dchar ch, Context ctx) {
    switch (ctx) {
        case Context.FlowOut: return ch.isNsPlainSafeOut;
        case Context.FlowIn: return ch.isNsPlainSafeIn;
        case Context.BlockOut: return ch.isNsPlainSafeOut;
        case Context.BlockIn: return ch.isNsPlainSafeIn;
        default: return false;
    }
}

private auto isNsPlain(dchar[] ch, Context ctx) {
    if (ch[0] != ':' && ch[0] != '#' && ch[0].isNsPlainSafe(ctx)) return true;
    if (ch.length < 2) return false;
    if (ch[1] == '#' && !ch[0].isWhite) return true;
    if (ch[0] == ':' && ch[1].isNsPlainSafe(ctx)) return true;
    return false;
}

class YamlDeserializer : Deserializer {
    string[string] tagHandles;
    ReadBuffer buffer;

    Context ctx;

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

    // https://yaml.org/spec/1.2.2/#rule-ns-uri-char
    private bool read_nsUriChar(ref dchar outCh) {
        auto c = this.buffer.front;
        switch (c) {
            case '%': {
                this.buffer.popFront();
                // TODO: should validate that it is a ns-hex-digit?
                ubyte[2] spl;
                c = this.buffer.front(); this.buffer.popFront();
                spl[0] = cast(ubyte)(c < 'A' ? c - '0' : c - 'A' + 10);
                c = this.buffer.front(); this.buffer.popFront();
                spl[1] = cast(ubyte)(c < 'A' ? c - '0' : c - 'A' + 10);
                c = cast(char)((spl[0] << 4) | spl[1]);
                goto Lsuccess;
            }
            case '#':
            case ';':
            case '?':
            case ':':
            case '@':
            case '&':
            case '=':
            case '+':
            case '$':
            case ',':
            case '_':
            case '.':
            case '!':
            case '~':
            case '*':
            case '\'':
            case '(':
            case ')':
            case '[':
            case ']':
                this.buffer.popFront();
                goto Lsuccess;
            default: {
                if (c.isNsWordChar) {
                    this.buffer.popFront();
                    goto Lsuccess;
                }
                break;
            }
        }
        return false;

        Lsuccess:
            outCh = c;
            return true;
    }

    private string read_nsUriChars() {
        string r = "";
        while (!this.buffer.empty) {
            dchar ch;
            if (!read_nsUriChar(ch)) break;
            r ~= ch;
        }
        return r;
    }

    private string read_nsTagChars() {
        string r = "";
        while (!this.buffer.empty) {
            auto ch = this.buffer.front;
            if (ch == '!' || ch.isFlowIndicator) break;
            if (!read_nsUriChar(ch)) break;
            r ~= ch;
        }
        return r;
    }

    private string read_nsWordChars() {
        string r = "";
        while (!this.buffer.empty) {
            dchar ch = this.buffer.front;
            if (!ch.isNsWordChar) break;
            this.buffer.popFront();
            r ~= ch;
        }
        return r;
    }

    private void consumeChar(char c, string msg) {
        if (this.buffer.front != c) {
            import std.conv : text;
            throw new YamlParsingException(msg ~ " but got |" ~ this.buffer.front.text ~ "|");
        }
        this.buffer.popFront();
    }

    private string read_tag() {
        this.buffer.skipWhitespace;

        if (this.buffer.front != '!') {
            return null;
        }
        this.buffer.popFront();

        switch (this.buffer.front) {
            case '<': {
                // verbatim tag
                this.buffer.popFront();
                string tag = this.read_nsUriChars();
                consumeChar('>', "Expected '>' to close verbatim tag opened with '!<'");
                this.buffer.skipWhitespace;
                return tag;
            }
            case '!': {
                // secondary tag handle
                this.buffer.popFront();

                auto prefix = "tag:yaml.org,2002:";
                auto prefixPtr = "!!" in this.tagHandles;
                if (prefixPtr !is null) {
                    prefix = *prefixPtr;
                }

                auto tag = prefix ~ this.read_nsTagChars();
                this.buffer.skipWhitespace;
                return tag;
            }
            default: break;
        }

        auto tag = this.read_nsWordChars();
        if (!this.buffer.empty && this.buffer.front == '!') {
            // was handle!
            this.buffer.popFront();
            auto prefixPtr = tag in this.tagHandles;
            if (prefixPtr is null) {
                throw new YamlParsingException("Unknown tag-handle '!" ~ tag ~ "!'");
            }
            tag = *prefixPtr;
        }
        tag ~= this.read_nsTagChars();
        this.buffer.skipWhitespace;
        return tag;
    }

    // Test tag parsing
    unittest {
        static immutable testCases = [
            "!<abc%20def>": "abc def",
            "!!str": "tag:yaml.org,2002:str",
            "!e!tag%21": "tag:example.com,2000:app/tag!",
            "!local": "local",
        ];
        foreach (inp, r; testCases) {
            try {
                auto de = new YamlDeserializer(inp);
                de.tagHandles["e"] = "tag:example.com,2000:app/";
                string tag = de.read_tag();
                assert(tag == r, "Failed parsing '" ~ inp ~ "'; expected '" ~ r ~ "' but got '" ~ tag ~ "'");
            }
            catch (YamlParsingException e) {
                assert(0, "Failed parsing '" ~ inp ~ "'; got YamlParsingException: " ~ e.message());
            }
        }
    }

    void read_basic(T)(ref T value) if (is(T == bool)) {
        auto tag = this.read_tag();
        // TODO: use the tag somehow...

        auto c = this.buffer.front.toLower;
        string rest;
        switch (c) {
            case 'y': rest = "es";   goto Lparse;
            case 'n': rest = "o";    goto Lparse;
            case 't': rest = "rue";  goto Lparse;
            case 'f': rest = "alse"; goto Lparse;

            Lparse: {
                bool f = (c == 'y' || c == 't');
                this.buffer.popFront();
                foreach (ch; rest) {
                    if (this.buffer.empty || this.buffer.front.toLower != ch) {
                        goto Lerr;
                    }
                    this.buffer.popFront();
                }
                value = f;
                return;
            }

            default: break;
        }

        Lerr:
            throw new YamlParsingException("Expected case-insensitive 'yes', 'no', 'true' or 'false'");
    }

    // Test bool parsing
    unittest {
        static immutable testCases = [
            "true": true,
            "trUe": true,
            "false": false,
            "yes": true,
            "Yes": true,
            "no": false
        ];
        foreach (s, r; testCases) {
            bool b = !r;
            try {
                (new YamlDeserializer(s)).read_basic(b);
            }
            catch (YamlParsingException e) {
                assert(0, "Failed parsing '" ~ s ~ "'; got YamlParsingException");
            }
            assert(b == r, "Failed parsing '" ~ s ~ "'; expected " ~ r ~ " but got " ~ b);
        }

        try {
            bool b;
            (new YamlDeserializer("z").read_basic(b));
            assert(0, "Failed parsing read_basic!bool with invalid data; expected YamlParsingException but none");
        }
        catch (YamlParsingException e) {}
        catch (Throwable e) {
            assert(0, "Failed parsing read_basic!bool with invalid data; expected YamlParsingException but got: " ~ e.toString());
        }
    }

    void read_basic(T)(ref T value) if (isScalarType!T && !is(T == bool)) {
        auto tag = this.read_tag();
        // TODO: use the tag somehow...

        static if (isFloatingPoint!T) {
            switch (this.buffer.front) {
                case '-': {
                    if (this.buffer.startsWith("-i")) {
                        goto Lerr;
                    }
                    else if (this.buffer.startsWith("-.inf")) {
                        this.buffer.popFrontExactly(5);
                        value = -T.infinity;
                        return;
                    }
                    break;
                }
                case '.': {
                    auto c = this.buffer.peek;
                    if (c == 'i' || c == 'n' ) {
                        this.buffer.popFront();
                    }
                    break;
                }
                case 'i':
                case 'n': {
                    goto Lerr;
                }
                default: break;
            }
        }

        try {
            value = parse!T(this.buffer);
            return;
        }
        catch (ConvException e) {
            throw new YamlParsingException("Failed parsing value of type " ~ T.stringof, e);
        }

        Lerr:
            throw new YamlParsingException("Expected floatingpoint value, '-.inf', '.inf' or '.nan'");
    }

    // Test float parsing
    unittest {
        static immutable float[string] testCases = [
            "!!float -1": -1.,
            "12.3": 12.3,
            "2.3e4": 2.3e4,
            ".inf": float.infinity,
            "-.inf": -float.infinity,
            ".nan": float.nan,
        ];
        foreach (inp, r; testCases) {
            float f = 0;
            try {
                auto de = new YamlDeserializer(inp);
                de.read_basic(f);
                assert(de.buffer.empty, "Failed parsing '" ~ inp ~ "'; still data left in buffer");
            }
            catch (YamlParsingException e) {
                assert(0, "Failed parsing '" ~ inp ~ "'; got YamlParsingException: " ~ e.message());
            }

            if (isNaN(r) && isNaN(f)) {
                continue;
            }
            assert(f == r, "Failed parsing '" ~ inp ~ "'; expected " ~ r.to!string ~ " but got " ~ f.to!string);
        }

        foreach (inp; ["-inf", "inf", "z"]) {
            try {
                float f;
                (new YamlDeserializer(inp)).read_basic(f);
                assert(0, "Failed parsing '" ~ inp ~ "'; expected YamlParsingException but got none");
            }
            catch (YamlParsingException e) {}
            catch (Throwable e) {
                assert(0, "Failed parsing read_basic!float with '" ~ inp ~ "'; expected YamlParsingException but got: " ~ e.toString());
            }
        }
    }

    // Test integer parsing
    unittest {
        static immutable int[string] testCases = [
            "!!int -1": -1,
            "12": 12
        ];
        foreach (inp, r; testCases) {
            int i = 0;
            try {
                auto de = new YamlDeserializer(inp);
                de.read_basic(i);
                assert(de.buffer.empty, "Failed parsing '" ~ inp ~ "'; still data left in buffer");
            }
            catch (YamlParsingException e) {
                assert(0, "Failed parsing '" ~ inp ~ "'; got YamlParsingException: " ~ e.message());
            }
            assert(i == r, "Failed parsing '" ~ inp ~ "'; expected " ~ r.to!string ~ " but got " ~ i.to!string);
        }
    }

    // Test character parsing (WIP)
    unittest {
        static immutable dchar[string] testCases = [
            "a": 'a',
            "💙": '💙',
        ];
        foreach (inp, r; testCases) {
            dchar ch = 0;
            try {
                auto de = new YamlDeserializer(inp);
                de.read_basic(ch);
                assert(de.buffer.empty, "Failed parsing '" ~ inp ~ "'; still data left in buffer");
            }
            catch (YamlParsingException e) {
                assert(0, "Failed parsing '" ~ inp ~ "'; got YamlParsingException: " ~ e.message());
            }
            assert(ch == r, "Failed parsing '" ~ inp ~ "'; expected " ~ r.to!string ~ " but got " ~ ch.to!string);
        }
    }

    private enum Chomping { Strip, Keep, Clip }

    // Reads an complete block header, that means both indentation indicator
    // AND chomping indicator.
    private void read_blockheader(ref Chomping chomp, ref ulong indentation) {
        chomp = Chomping.Clip;
        indentation = 0;

        auto ch = this.buffer.front;
        switch (ch) {
            case '-': chomp = Chomping.Strip; break;
            case '+': chomp = Chomping.Keep; break;
            default: goto LindentIndicator;
        }
        this.buffer.popFront();
        ch = this.buffer.front();

        LindentIndicator:
        if (ch >= '1' && ch <= '9') {
            indentation = cast(byte)(ch - '0');
            this.buffer.popFront();
            ch = this.buffer.front();
        }

        if (chomp != Chomping.Clip) return;

        switch (ch) {
            case '-': chomp = Chomping.Strip; break;
            case '+': chomp = Chomping.Keep; break;
            default: return;
        }
        this.buffer.popFront();
    }

    void read_string(T)(ref T str) if (isSomeString!T) {
        auto tag = this.read_tag();
        // TODO: use the tag somehow...
        // TODO: what to do when nothing could be parsed?

        switch (this.buffer.front) {
            case '"': {
                // Parse escaped string
                this.buffer.popFront();

                // TODO: check if this is right...
                // https://yaml.org/spec/1.2.2/#731-double-quoted-style
                str = backslashUnescape(this.buffer, '"');

                consumeChar('"', "Expected string end");
                return;
            }
            case '\'': {
                // Parse non-escaped string
                this.buffer.popFront();
                str = "";
                dchar ch;
                while (!this.buffer.empty) {
                    ch = this.buffer.front;
                    if (ch == '\'') break;
                    this.buffer.popFront();
                    str ~= ch;
                }
                consumeChar('\'', "Expected string end");
                return;
            }
            case '|':
            case '>':
            {
                bool isFolded = this.buffer.front == '>';
                this.buffer.popFront();

                Chomping chomp; ulong indent;
                read_blockheader(chomp, indent);

                this.buffer.skipWsNoNl;
                consumeChar('\n', "Expected newline");

                if (indent == 0) {
                    // Count whitespaces in the front...
                    indent = countUntil!("a != ' '")(this.buffer, []);

                    if (indent == 0) {
                        str = "";
                        return;
                    }
                }

                str = "";

                int tmpLinebreaks = 0;
                while (!this.buffer.empty) {
                    ulong prefix = countUntil!("a != ' '")(this.buffer, []);
                    if (prefix < indent) break;
                    this.buffer.popFrontExactly(prefix);

                    char[] line; dchar ch;
                    while (!this.buffer.empty) {
                        ch = this.buffer.front;
                        this.buffer.popFront;
                        line ~= ch;
                        if (ch == '\n') break;
                    }

                    if (line == "\n") {
                        tmpLinebreaks++;
                        continue;
                    } else {
                        foreach (i; 0..tmpLinebreaks) {
                            if (isFolded) str ~= ' ';
                            else str ~= '\n';
                        }
                        tmpLinebreaks = 0;
                    }

                    if (isFolded && line[$-1] == '\n') {
                        tmpLinebreaks++;
                        line = line[0..$-1];
                    }

                    str ~= line;
                }

                // All trailing linebreaks...
                foreach (i; 0..tmpLinebreaks) {
                    str ~= '\n';
                }

                final switch (chomp) {
                    case Chomping.Strip: {
                        while (str.length > 0 && str[$-1] == '\n')
                            str = str[0..$-1];
                        break;
                    }
                    case Chomping.Keep: break;
                    case Chomping.Clip: {
                        while (str.length > 1 && str[$-1] == '\n' && str[$-2] == '\n')
                            str = str[0..$-1];
                        break;
                    }
                }

                return;
            }
            default: break;
        }

        auto ch = this.buffer.front;
        if (
            !ch.isIndicator
            || (
                (ch == '?' || ch == ':' || ch == '-')
                && this.buffer.peek.isNsPlainSafe(this.ctx)
            )
        ) {
            // plain style string!
            // https://yaml.org/spec/1.2.2/#733-plain-style
            str = "";
            str ~= ch;
            this.buffer.popFront;

            while (!this.buffer.empty) {
                ch = this.buffer.front();
                if (ch != ':' && ch != '#' && ch.isNsPlainSafe(ctx)) {
                    str ~= ch;
                    this.buffer.popFront();
                    continue;
                }
                if (!this.buffer.hasNext) break;

                if (
                    (ch == ':' && this.buffer.peek.isNsPlainSafe(ctx))
                    || (ch == '#' && !str[$-1].isWhite)
                ) {
                    str ~= ch;
                    this.buffer.popFront();
                    continue;
                }
                break;
            }
        }
    }

    // Test string parsing - normal
    unittest {
        import std.conv : text;
        static immutable testCases = [
            "\"a\\nb\"": "a\nb",
            "\'a\\nb\'": "a\\nb",

            "|\n  a\n  b\n  \n": "a\nb\n",
            "|-\n  a\n  b\n  \n": "a\nb",
            "|+\n  a\n  b\n  \n": "a\nb\n\n",

            ">\n  a\n  b\n  \n": "a b\n",
            ">-\n  a\n  b\n  \n": "a b",
            ">+\n  a\n  b\n  \n": "a b\n\n",

            "abc": "abc",
        ];
        foreach (inp, r; testCases) {
            string str;
            try {
                auto de = new YamlDeserializer(inp);
                de.read_string(str);
                assert(de.buffer.empty, "Failed parsing " ~ [inp].text[1..$-1] ~ "; still data left in buffer");
            }
            catch (YamlParsingException e) {
                assert(0, "Failed parsing " ~ [inp].text[1..$-1] ~ "; got YamlParsingException: " ~ e.message());
            }
            assert(str == r, "Failed parsing " ~ [inp].text[1..$-1] ~ "; expected " ~ [r].text[1..$-1] ~ " but got " ~ [str].text[1..$-1] ~ "");
        }
    }

    // Test string parsing - comments
    unittest {
        import std.conv : text;
        static immutable testCases = [
            "abc#": "abc#",
            "abc #": "abc",

            // Comments are NOT removed from block-style strings
            "|\n  a # zz\n  b": "a # zz\nb",
        ];
        foreach (inp, r; testCases) {
            string str;
            try {
                auto de = new YamlDeserializer(inp);
                de.read_string(str);
            }
            catch (YamlParsingException e) {
                assert(0, "Failed parsing " ~ [inp].text[1..$-1] ~ "; got YamlParsingException: " ~ e.message());
            }
            assert(str == r, "Failed parsing " ~ [inp].text[1..$-1] ~ "; expected " ~ [r].text[1..$-1] ~ " but got " ~ [str].text[1..$-1] ~ "");
        }
    }

    override void read_ignore() {
        throw new YamlParsingException("read_ignore is NIY!");
    }

}

void fromYaml(T)(auto ref T value, string inp) {
    auto de = new YamlDeserializer(inp);
    value.deserialize(de);
}
void fromYaml(T)(auto ref T value, ReadBuffer.Source source) {
    auto de = new YamlDeserializer(source);
    value.deserialize(de);
}
void fromYaml(T)(auto ref T value, ReadBuffer.Source.FnT source) {
    auto de = new YamlDeserializer(source);
    value.deserialize(de);
}
void fromYaml(T)(auto ref T value, ReadBuffer.Source.DgT source) {
    auto de = new YamlDeserializer(source);
    value.deserialize(de);
}

pragma(inline) T parseYaml(T)(string inp) {
    T val = T.init;
    static if (is(T == class)) {
        val = new T();
    }
    val.fromYaml(inp);
    return val;
}
