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
 * Module to hold some common code, used by multiple formats.
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2024 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/mai-lapyst, Mai-Lapyst)
 */
module serde.common;

import std.conv : to;
import std.range : empty, front, popFront, ElementType, isInputRange;

import ninox.std.callable;
import ninox.std.traits : RefT;

/// Basic escape function that does slash escaption like in JSON strings
void backslashEscape(alias Sink)(const(ubyte)[] chars) {
    size_t tmp = 0;
    foreach (i, c; chars) {
        char d;
        switch (c) {
            case '\"': d = '"'; goto simple;
            case '\\': d = c; goto simple;
            case '\b': d = 'b'; goto simple;
            case '\f': d = 'f'; goto simple;
            case '\n': d = 'n'; goto simple;
            case '\r': d = 'r'; goto simple;
            case '\t': d = 't'; goto simple;
            case '\0': d = '0'; goto simple;
            simple: {
                Sink(chars[tmp .. i]);
                tmp = i + 1;

                Sink([ '\\', d ]);
                continue;
            }

            case '\1': .. case '\u0007':
            case '\u000e': .. case '\u001f':
            case '\u000b':
            case '\u00ff':
            {
                Sink(chars[tmp .. i]);
                tmp = i + 1;

                ubyte[2] spl;
                spl[0] = c >> 4;
                spl[1] = c & 0xF;
                Sink([
                    '\\', 'u', '0', '0',
                    cast(ubyte)( spl[0] < 10 ? spl[0] + '0' : spl[0] - 10 + 'A' ),
                    cast(ubyte)( spl[1] < 10 ? spl[1] + '0' : spl[1] - 10 + 'A' )
                ]);
                continue;
            }

            default:
                break;
        }
    }
    Sink(chars[tmp .. chars.length]);
}

string backslashUnescape(R)(auto ref R inp, char delimiter)
if (isInputRange!R)
{
    string r;
    ElementType!R c;
    while (!inp.empty()) {
        c = inp.front();
        if (c == delimiter) {
            break;
        } else if (c == '\\') {
            inp.popFront();
            c = inp.front(); inp.popFront();
            switch (c) {
                case '"':
                case '\\': {
                    r ~= c;
                    continue;
                }

                case 'b': { r ~= '\b'; continue; }
                case 'f': { r ~= '\f'; continue; }
                case 'n': { r ~= '\n'; continue; }
                case 'r': { r ~= '\r'; continue; }
                case 't': { r ~= '\t'; continue; }
                case '0': { r ~= '\0'; continue; }

                case 'u': {
                    c = inp.front(); inp.popFront();
                    if (c != '0') throw new Exception("Unescape error: expected '0' after '\\u'");
                    c = inp.front(); inp.popFront();
                    if (c != '0') throw new Exception("Unescape error: expected '0' after '\\u0'");

                    ubyte[2] spl;
                    c = inp.front(); inp.popFront();
                    spl[0] = cast(ubyte)(c < 'A' ? c - '0' : c - 'A' + 10);
                    c = inp.front(); inp.popFront();
                    spl[1] = cast(ubyte)(c < 'A' ? c - '0' : c - 'A' + 10);

                    c = cast(char)((spl[0] << 4) | spl[1]);
                    r ~= c;
                    continue;
                }

                default:
                    throw new Exception("Invalid escape sequence: \\" ~ c.to!string);
            }
        } else {
            inp.popFront();
            r ~= c;
        }
    }
    return r;
}

struct ReadBuffer {
public:
    alias Source = Callable!(size_t, RefT!(char[]), size_t);
protected:
    enum BufferSize = 4069 * 4;

    Source source;
    size_t len, pos = 0;
    char[] data = void;

public:
    this(char[] data) {
        this.data = data;
        this.len = data.length;
    }

    this(Source source) {
        this.source = source;
    }
    this(Source.FnT source) {
        this.source = source;
    }
    this(Source.DgT source) {
        this.source = source;
    }

    /// Fills up the internal buffer
    private void fill(bool handleEOF = true) {
        if (!this.source) {
            if (handleEOF) throw new Exception("End of file reached");
        }

        this.len = this.source(this.data, BufferSize);
        if (handleEOF && this.len < 1) {
            throw new Exception("End of file reached");
        }
        this.pos = 0;
    }

    /// Checks if filling is needed and fills the buffer (only when the buffer is completly empty!)
    pragma(inline) void fillIfNeeded(bool handleEOF = true) {
        if (this.pos >= this.len) {
            this.fill(handleEOF);
        }
    }

    /// Checks if the parser is at the end
    /// 
    /// Returns: true if the parser is at the end; false otherwise
    @property bool empty() {
        this.fillIfNeeded(false);
        return this.pos >= this.len;
    }

    /// Gets the current char in the buffer
    /// 
    /// Note: Fills the internal buffer if needed via `fillIfNeeded()`.
    /// 
    /// Returns: the char at the current position in the internal buffer
    @property dchar front() {
        this.fillIfNeeded();

        import std.utf : decode;
        size_t i = this.pos;
        return decode(this.data, i);
    }

    void popFront() {
        char c = this.data[this.pos];
        if (c >= 0xF0) this.pos += 4;
        else if (c >= 0xE0) this.pos += 3;
        else if (c >= 0xC0) this.pos += 2;
        else this.pos += 1;
    }
}
