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
 * Module to hold all basic exception classes.
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2024 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/mai-lapyst, Mai-Lapyst)
 */
module serde.error;

class SerdeException : Exception {
    this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable nextInChain = null) pure nothrow @nogc @safe {
        super(msg, file, line, nextInChain);
    }
    this(string msg, Throwable nextInChain, string file = __FILE__, size_t line = __LINE__) pure nothrow @nogc @safe {
        super(msg, file, line, nextInChain);
    }
}

class MissingFieldException : SerdeException {
    string type;
    string field_name;

    this(
        string type, string field_name,
        string file = __FILE__, size_t line = __LINE__, Throwable nextInChain = null
    ) pure nothrow @safe {
        this.type = type;
        this.field_name = field_name;
        super("Missing field '" ~ field_name ~ "' of type '" ~ type ~ "'", file, line, nextInChain);
    }
}

class DuplicateFieldException : SerdeException {
    string type;
    string field_name;

    this(
        string type, string field_name,
        string file = __FILE__, size_t line = __LINE__, Throwable nextInChain = null
    ) pure nothrow @safe {
        this.type = type;
        this.field_name = field_name;
        super("Duplicate field '" ~ field_name ~ "' for type '" ~ type ~ "'", file, line, nextInChain);
    }
}

class UnknownFieldException : SerdeException {
    string type;
    string field_name;

    this(
        string type, string field_name,
        string file = __FILE__, size_t line = __LINE__, Throwable nextInChain = null
    ) pure nothrow @safe {
        this.type = type;
        this.field_name = field_name;
        super("Unknown field '" ~ field_name ~ "' for type '" ~ type ~ "'", file, line, nextInChain);
    }
}

class InvalidValueException : SerdeException {
    this(
        string msg, string file = __FILE__, size_t line = __LINE__, Throwable nextInChain = null
    ) pure nothrow @safe @nogc {
        super(msg, file, line, nextInChain);
    }
}
