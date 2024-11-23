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
 * Module to hold all code for the external typetag format.
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2024 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/mai-lapyst, Mai-Lapyst)
 */
module serde.typetag.external;

/// Must be placed **inside** a baseclass or interface.
/// 
/// Creates the neccessary typetag-base via the TypetagBase template,
/// as well as a `deserializeInstance` and a `serializeInstance` static function to
/// deserialize / serialize an instance.
/// 
/// Uses the "externally tagged" format, where the tag is the key, and the value is the instance.
/// Note: it must be the first and only key inside the map.
/// ```
/// mixin TypetagExternal!()
/// =>
/// { "x": {...} }
/// ```
template TypetagExternal() {
    static import serde.ser;
    static import serde.de;
    static import serde.typetag;

    mixin serde.typetag.TypetagBase!();

    static void deserializeInstance(ref typeof(this) instance, serde.de.Deserializer de) {
        import serde, serde.error;

        auto map = de.read_map();

        AnyValue rawKey;
        if (!map.read_key(rawKey)) {
            throw new SerdeException("Cannot deserialize empty object");
        }

        auto key = rawKey.get!string;
        auto ptr = key in typetag_registry();
        if (ptr is null) {
            throw new SerdeException("Could not find type '" ~ key ~ "' for " ~ typeof(this).stringof);
        }
        (*ptr)(instance, map.read_value());

        map.end();
    }

    static void serializeInstance(ref typeof(this) instance, serde.ser.Serializer ser) {
        auto s = ser.start_struct();
        auto field_ser = s.write_field(instance.typetag_name());
        auto field_s = field_ser.start_struct();
        instance.typetag_serialize(field_s);
        field_s.end();
        s.end();
    }
}

unittest {
    import serde.typetag, serde.base, serde;

    interface Base {
        mixin TypetagExternal!();
    }
    static class Extend : Base {
        string user;
        this() {}
        this(string user) { this.user = user; }
        mixin RegisterTypetag!(Base, "ext");
    }

    static class FooSerializer : BaseSerializer {
        string output;
        override void write_string(string str) {
            output ~= str;
        }
        class Struct : Serializer.Struct {
            bool atStart = true;
            Serializer write_field(string name) {
                if (!atStart) output ~= ",";
                atStart = false;
                output ~= name ~ ":";
                return this.outer;
            }
            void end() {
                output ~= "}";
            }
        }
        override Struct start_struct() {
            output ~= "{";
            return new Struct();
        }
    }
    string toFoo(T)(T v) {
        auto ser = new FooSerializer();
        v.serialize(ser);
        return ser.output;
    }

    {
        Base b = new Extend("foo");
        assert( toFoo(b) == "{ext:{user:foo}}" );
    }
    {
        AnyMap inp;
        inp["ext"] = AnyMap([ "user": "foo" ]);
        Base b = null;
        b.deserialize(new AnyValueDeserializer(AnyValue(inp)));
        assert(b !is null);
        assert((cast(Extend)b) !is null);
        assert((cast(Extend)b).user == "foo");
    }
}
