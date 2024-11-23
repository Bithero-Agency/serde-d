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
 * Module to hold all code for the tuple typetag format.
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2024 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/mai-lapyst, Mai-Lapyst)
 */
module serde.typetag.tuple;

/// Must be placed **inside** a baseclass or interface.
/// 
/// Creates the neccessary typetag-base via the TypetagBase template,
/// as well as a `deserializeInstance` and a `serializeInstance` static function to
/// deserialize / serialize an instance.
/// 
/// Uses the "tuple tagged" format, where the container is an tuple with length 2,
/// the tag being at index 0, and the value at index 1:
/// ```
/// mixin TypetagTuple!()
/// =>
/// [ "x", ... ]
/// ```
template TypetagTuple() {
    static import serde.ser;
    static import serde.de;
    static import serde.typetag;

    mixin serde.typetag.TypetagBase!();

    static void deserializeInstance(ref typeof(this) instance, serde.de.Deserializer de) {
        import serde, serde.typetag, serde.error;

        auto tuple = de.read_tuple();

        auto elem_de = tuple.read_element();
        if (elem_de is null) {
            throw new SerdeException("Cannot deserialize " ~ typeof(this).stringof ~ " from an empty tuple");
        }

        string key;
        key.deserialize(elem_de);
        auto ptr = key in typetag_registry();
        if (ptr is null) {
            throw new SerdeException("Could not find type '" ~ key ~ "' for " ~ typeof(this).stringof);
        }

        elem_de = tuple.read_element();
        if (elem_de is null) {
            throw new SerdeException("Cannot deserialize " ~ typeof(this).stringof ~ " without value");
        }
        (*ptr)(instance, elem_de);

        tuple.end();
    }

    static void serializeInstance(ref typeof(this) instance, serde.ser.Serializer se) {
        auto tuple = se.start_tuple();
        instance.typetag_name().serialize( tuple.write_element() );

        auto value_ser = tuple.write_element();
        auto value_struct = value_ser.start_struct();
        instance.typetag_serialize(value_struct);
        value_struct.end();

        tuple.end();
    }
}

unittest {
    import serde.typetag, serde.base, serde;

    interface Base {
        mixin TypetagTuple!();
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
        class Tuple : Serializer.Tuple {
            bool atStart = true;
            Serializer write_element() {
                if (!atStart) output ~= ",";
                atStart = false;
                return this.outer;
            }
            void end() {
                output ~= "]";
            }
        }
        override Tuple start_tuple() {
            output ~= "[";
            return new Tuple();
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
        assert( toFoo(b) == "[ext,{user:foo}]" );
    }
    {
        AnyValue[] inp = [
            AnyValue("ext"),
            AnyValue( AnyMap([ "user": "foo" ]) ),
        ];
        Base b = null;
        b.deserialize(new AnyValueDeserializer(AnyValue(inp)));
        assert(b !is null);
        assert((cast(Extend)b) !is null);
        assert((cast(Extend)b).user == "foo");
    }
}
