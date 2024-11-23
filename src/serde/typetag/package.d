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
 * Module to hold all code for the typetag feature of serde-d.
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2024 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/mai-lapyst, Mai-Lapyst)
 */
module serde.typetag;

public import serde.typetag.adjacent;
public import serde.typetag.external;
public import serde.typetag.internal;
public import serde.typetag.tuple;

/// Must be placed **inside** a baseclass or interface.
/// 
/// Base for all Typetag* templates; creates:
///  - an `typetag_registry` static function for decendant types to
///    register themselfs to via the `RegisterTypetag` template,
///  - defines a `typetag_name` member for decendants to expose their name and
///  - defines `typetag_serialize`, which is used by the typetag format to call the serializer.
template TypetagBase() {
    static auto ref typetag_registry() {
        import serde.de;
        alias deserializeFn = void function(ref typeof(this) a, Deserializer de);
        static deserializeFn[string] reg;
        return reg;
    }

    string typetag_name();

    static import serde.ser;

    void typetag_serialize(serde.ser.Serializer.Struct s);
}

/// Must be placed **inside** a decendant class.
/// 
/// It registers the current decendant class as a deserializeable decendant of `BaseType`,
/// identified by the given `name`.
template RegisterTypetag(alias BaseType, string name)
{
    shared static this() {
        import serde.de;
        static void doDeserialize(ref BaseType val, Deserializer de) {
            typeof(this) self;
            self.deserialize(de);
            val = self;
        }
        auto ptr = name in BaseType.typetag_registry();
        assert(ptr is null);
        BaseType.typetag_registry()[name] = &doDeserialize;
    }

    override string typetag_name() {
        return name;
    }

    static import serde.ser, serde.attrs;

    @(serde.attrs.SerdeSkip)
    override void typetag_serialize(serde.ser.Serializer.Struct s) {
        this.serializeInto(s);
    }
}
