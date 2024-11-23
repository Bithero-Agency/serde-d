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
 * Module to hold all code for the adjacent typetag format.
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2024 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/mai-lapyst, Mai-Lapyst)
 */
module serde.typetag.adjacent;

/// Must be placed **inside** a baseclass or interface.
/// 
/// Creates the neccessary typetag-base via the TypetagBase template,
/// as well as a `deserializeInstance` and a `serializeInstance` static function to
/// deserialize / serialize an instance.
/// 
/// Uses the "adjacent tagged" format, where the tag and the instance have their own keys.
/// ```
/// mixin TypetagAdjacent!("type", "value")
/// =>
/// { "type": "x", "value": {...} }
/// ```
template TypetagAdjacent(string tag, string value) {
    static import serde.ser;
    static import serde.de;
    static import serde.typetag;

    mixin serde.typetag.TypetagBase!();

    static void deserializeInstance(ref typeof(this) instance, serde.de.Deserializer de) {
        import serde, serde.error;

        auto map = de.read_map();

        AnyValue rawKey, rawInstance;
        while (map.read_key(rawKey)) {
            auto key = rawKey.get!string;
            if (key == tag) {
                string tag_value;
                tag_value.deserialize(map.read_value());
                auto ptr = tag_value in typetag_registry();
                if (ptr is null) {
                    throw new SerdeException("Could not find type '" ~ key ~ "' for " ~ typeof(this).stringof);
                }
                if (rawInstance.hasValue) {
                    map.end();
                    (*ptr)(instance, new AnyValueDeserializer(rawInstance));
                    return;
                }

                if (!map.read_key(rawKey)) {
                    throw new SerdeException("Missing '" ~ value ~ "' key for " ~ typeof(this).stringof);
                }
                key = rawKey.get!string;
                if (key != value) {
                    throw new SerdeException(
                        "Unknown key '" ~ key ~ "', expected '" ~ value ~ "' for " ~ typeof(this).stringof
                    );
                }
                (*ptr)(instance, map.read_value());
                map.end();
                return;
            }
            else if (key == value) {
                rawInstance.deserialize(map.read_value());
                continue;
            }
            else {
                throw new SerdeException(
                    "Unknown key '" ~ key ~ "', expected either '" ~ tag ~ "' or '" ~ value ~ "' for "
                        ~ typeof(this).stringof
                );
            }
        }
        throw new SerdeException(
            "Cannot deserialize " ~ typeof(this).stringof ~ " from empty object"
        );
    }

    static void serializeInstance(ref typeof(this) instance, serde.ser.Serializer ser) {
        auto s = ser.start_struct();
        instance.typetag_name().serialize( s.write_field(tag) );

        auto field_ser = s.write_field(value);
        auto field_s = field_ser.start_struct();
        instance.typetag_serialize(field_s);
        field_s.end();

        s.end();
    }
}

unittest {
    import serde.typetag, serde.base, serde;

    interface Base {
        mixin TypetagAdjacent!("type", "value");
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
        assert( toFoo(b) == "{type:ext,value:{user:foo}}" );
    }
    {
        AnyMap inp;
        inp["type"] = "ext";
        inp["value"] = AnyMap([ "user": "foo" ]);
        Base b = null;
        b.deserialize(new AnyValueDeserializer(AnyValue(inp)));
        assert(b !is null);
        assert((cast(Extend)b) !is null);
        assert((cast(Extend)b).user == "foo");
    }
}
