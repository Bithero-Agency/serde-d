module serde.main;

import serde.ser;
import serde.json;
import serde.yaml;
import serde.attrs;
import std.container : SList;
import std.typecons : Tuple;

struct Vec2 {
    int x, y;
}

/*enum Planets : Vec2 {
    A = Vec2(0, 0),
}*/

class Test {
    @(Serde.Rename(
        deserialize: "j",
        serialize: "z",
    ))
    int i;

    //@(Serde.Raw)
    //string r = "{\"a\":2}";

    string[] vec = ["a\nb", "b"];

    int[string] map = [
        "aa": 12,
        "bb": 35,
        "a\nb": 11,
    ];

    /*Tuple!(int, "a", int) t;

    MyRange mr;

    @(Serde.Getter, Serde.Rename("j"))
    int get_j() {
        return 42;
    }

    @property void flag(bool b) {}
    @property bool flag() { return false; }

    @(Serde.Getter, Serde.Raw)
    string get_raw() { return "zz"; }

    Vec2 pos = Vec2(12, 55);*/

    string s = "a\nb\n\n";
    int zz = 2;

    // @(Serde.Flatten)
    // int[string] map = [
    //     "Mercury": 0.4,
    //     "Venus": 0.7,
    // ];

    //SList!string l;
    //this() {
    //    l.insertFront("b");
    //    l.insertFront("a");
    //}

    void serialize2(S : Serializer)(S ser) {
        auto s = ser.start_struct!(typeof(this))();
        s.write_field("i", this.i);
        s.write_field("vec", this.vec);
        s.write_field("map", this.map);
        s.write_field("t", this.t);
        s.write_field("mr", this.mr);
        s.end();
    }
}

struct MyRange {
    string[] values = ["c", "d"];
    int idx = 0;

    bool empty() { return idx >= values.length; }
    string front() { return values[idx]; }
    void popFront() { idx++; }
    ulong length() { return values.length; }
}

void main() {
    import std.stdio;
    Test t = new Test();
    writeln(t.toPrettyJson());
    writeln(t.toYaml());
}