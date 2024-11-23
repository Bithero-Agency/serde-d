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
module serde.typetag.internal;

import serde.ser;
import serde.de;
import serde.error;
import serde.value;
import serde.typetag : TypetagBase;

import std.typecons : Tuple, tuple;

/// Deserializer for an internally tagged class.
/// This means that the tag is stored alongside all other properties.
class InternallyTaggedDeserializer : Deserializer {
    static struct Entry {
        AnyValue val;
        string key;
    }
    Entry[] entries;
    Deserializer.MapAccess base;

    this(Entry[] entries, Deserializer.MapAccess base) {
        this.entries = entries;
        this.base = base;
    }

    override void read_bool(ref bool b) {
        throw new SerdeException("Should not invoke read_bool on InternallyTaggedDeserializer");
    }
    override void read_signed(ref long l, ubyte sz) {
        throw new SerdeException("Should not invoke read_signed on InternallyTaggedDeserializer");
    }
    override void read_unsigned(ref ulong l, ubyte sz) {
        throw new SerdeException("Should not invoke read_unsigned on InternallyTaggedDeserializer");
    }
    override void read_float(ref double f, ubyte sz) {
        throw new SerdeException("Should not invoke read_float on InternallyTaggedDeserializer");
    }
    override void read_real(ref real r) {
        throw new SerdeException("Should not invoke read_real on InternallyTaggedDeserializer");
    }
    override void read_char(ref dchar c) {
        throw new SerdeException("Should not invoke read_char on InternallyTaggedDeserializer");
    }

    override void read_string(ref string str) {
        throw new SerdeException("Should not invoke read_string on InternallyTaggedDeserializer!");
    }

    override void read_ignore() {
        throw new SerdeException("Should not invoke read_ignore on InternallyTaggedDeserializer!");
    }

    override void read_any(ref AnyValue value) {
        throw new SerdeException("Should not invoke read_any on InternallyTaggedDeserializer!");
    }

    override void read_enum(ref AnyValue value) {
        throw new SerdeException("Should not invoke read_enum on InternallyTaggedDeserializer!");
    }

    override Deserializer.SeqAccess read_seq() {
        throw new SerdeException("Should not invoke read_seq on InternallyTaggedDeserializer!");
    }
    override Deserializer.SeqAccess read_tuple() {
        throw new SerdeException("Should not invoke read_tuple on InternallyTaggedDeserializer!");
    }

    class MapAccess : Deserializer.MapAccess {
        override bool read_key(ref AnyValue key) {
            if (entries.length > 0) {
                key = entries[0].key;
                return true;
            }
            return base.read_key(key);
        }

        override Deserializer read_value() {
            if (entries.length > 0) {
                auto de = new AnyValueDeserializer(entries[0].val);
                entries = entries[1..$];
                return de;
            } else {
                return base.read_value();
            }
        }

        override void ignore_value() {
            if (entries.length > 0) {
                entries = entries[1..$];
            } else {
                base.ignore_value();
            }
        }

        override void end() {
            base.end();
        }
    }

    override MapAccess read_map() {
        return new MapAccess();
    }

    override MapAccess read_struct() {
        return new MapAccess();
    }
}

/// Must be placed **inside** a baseclass or interface.
/// 
/// Creates the neccessary `typetag_registry` static function for decendants to regiter themselfs to,
/// as well as a `deserializeInstance` static function to deserialize an instance.
/// 
/// Uses the "internally tagged" format, where the tag property is right besides all other properties
/// of the struct/class:
/// ```
/// mixin TypetagInternal!("type")
/// =>
/// { "type": "x", ... }
/// ```
template TypetagInternal(string tag) {
    static import serde.ser;
    static import serde.de;
    static import serde.typetag;

    mixin serde.typetag.TypetagBase!();

    static void deserializeInstance(ref typeof(this) a, serde.de.Deserializer de) {
        import serde : AnyValue;
        import serde.typetag;

        auto map = de.read_map();
        InternallyTaggedDeserializer.Entry[] entries;
        AnyValue rawKey;
        while (map.read_key(rawKey)) {
            auto key = rawKey.get!string;
            if (key == tag) {
                string value;
                value.deserialize(map.read_value());
                auto ptr = value in typetag_registry();
                if (ptr is null) {
                    throw new Exception("could not find deserializer target");
                }
                (*ptr)( a, new InternallyTaggedDeserializer(entries, map) );
                return;
            }
            else {
                AnyValue rawVal;
                rawVal.deserialize(map.read_value());
                entries ~= InternallyTaggedDeserializer.Entry(rawVal, key);
            }
        }
        throw new Exception("Could not find any type key...");
    }

    static void serializeInstance(ref typeof(this) instance, serde.ser.Serializer se) {
        auto s = se.start_struct();
        instance.typetag_name().serialize( s.write_field(tag) );
        instance.typetag_serialize(s);
        s.end();
    }
}

unittest {
    import serde.typetag, serde.base, serde;

    interface Base {
        mixin TypetagInternal!("type");
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
        assert( toFoo(b) == "{type:ext,user:foo}" );
    }
    {
        AnyMap inp;
        inp["type"] = "ext";
        inp["user"] = "foo";
        Base b = null;
        b.deserialize(new AnyValueDeserializer(AnyValue(inp)));
        assert(b !is null);
        assert((cast(Extend)b) !is null);
        assert((cast(Extend)b).user == "foo");
    }
}
