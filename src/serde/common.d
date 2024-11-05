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
