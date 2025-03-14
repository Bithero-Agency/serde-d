# serde.d

A serialization and deserialization framework for dlang.

## License

The code in this repository is licensed under AGPL-3.0-or-later; for more details see the LICENSE file in the repository.

## How it works

See the `documentation` folder in the source repo for more information (located at https://codearq.net/bithero-dlang/serde.d/src/branch/master/documentation)

## Usage

To start using serde, you'll first need to find and add an serde-serializer package that provides you with an actual serilizer, such as:

- `serde-d:json` - JSON support
- `serde-d:yaml` - Yaml support

### Serializing

Each package *should* define an serializer in the `<package>.ser` module, named `<format>Serializer`. Additionally, the same module should hold an ufcs function `to<format>(T)(ref T val)`. It's convention to re-export this module in the top-most module of your package via `public import`.

For example, when using `serde-d:json`, this is `serde.json.ser.JsonSerializer` and `toJson`:

```d
import std.stdio : writeln;
import serde.json;

struct MyObj {
    int i = 12;
}

void main() {
    writeln( MyObj().toJson() ); // Will print {"i":12}
}
```

> Note: By default, all fields **and** all functions marked with `@property` are deserialized / serialized.

To overwrite this, each type can implement an `serialize` method (optionally via ufcs, but for that you need to use `@(Serde.UseUfcs)`):

```d
import serde.ser : Serializer;

struct MyObj {
    int i = 12;

    void serialize(Serializer ser) {
        auto s = ser.start_struct();
        (this.i * 2).serialize( s.write_field("j") );
        s.end();
    }
}
```

> Note: for more infromation how to paragmatically use the serializer (including `serializeInstance`), see `documentation/types.md` and `documentation/serializers.md`.

### Deserializing

Really just the reverse of the serializing; the same things as before apply here, but with different names: The deserializer *should* be defined in `<package>.de`, named `<format>Deserializer`, and provide atleast the ufcs functions `T parse<format>(T)(...)` and `from<format>(T)(auto ref T value, ...)`. Like before, it is convention to re-export this module in the top-most module of your package.

For example, when using `serde-d:json`, this is `serde.json.de.JsonDeserializer` and `parseJson` / `fromJson`:

```d
import std.stdio : writeln;
import serde.json;

struct MyObj {
    int i = 12;
}

void main() {
    assert( parseJson!MyObj(`{"i":12}`).i == 12 );

    MyObj obj;
    obj.fromJson(`{"i":12}`);
    assert(obj.i == 12);
}
```

> Note: This demonstrates why both an `parse*` and `from*` variant should be present: the `parse*` family is for completly parsing an instance, while the `from*` family is to parse *into* an existing instance.

To overwrite this, each type can implement an `deserialize` method (optionally via ufcs, but for that you need to use `@(Serde.UseUfcs)`):

```d
import serde : Deserializer, AnyValue;

struct MyObj {
    int i = 12;

    void deserialize(Deserializer ser) {
        auto s = ser.read_struct();
        AnyValue key;
        while (s.read_key(field)) {
            string field = key.get!string;
            switch (field) {
                case "i":
                    this.i.deserialize(s.read_value());
                    break;
                default:
                    s.ignore_value();
                    break;
            }
        }
        s.end();
    }
}
```

> Note: for more infromation how to paragmatically use the deserializer (including `deserializeInstance`), see `documentation/types.md` and `documentation/deserializers.md`.

### Interfaces and inheritance

To sucessfully serialize & deserialize types with inheritance or interfaces, please see `documentation/typetag.md`.

### Attributes

The package comes with an set of attributes, that can be used to tweak the default implementation of `serialize` and `deserialize` for strucs and classes. These live all in `serde.attrs`, but are re-exported in `serde` so you can just write `import serde;` and are good to go.

There are two ways of writing these attributes in your code: `Serde.Skip` and `SerdeSkip`. The only difference between the two is that the second one is only for convinience, because dlang dosnt supports dot-notation without parenteseses:
```d
@Serde.Skip   // This won't work sadly...
@SerdeSkip    // but this will
@(Serde.Skip) // and this too
```

- `Serde.UseUfcs`: due to limitations of dlang's compiletime features, ufcs methods cannot be discovered by template magic. Since serde works by expecting that the expression `x.serialize(serializer)` compiles, the default implementation for `serialize` for structs and classes only looks if it has an member called `serialize`; if not it concludes it doesnt implements an own serialize method and generates one. However, this completly ignores ufcs methods like `void serialize(S)(X x, S serializer)`. To allow you to write these methods in an ufcs way, you simple need to annotate the struct or class with this attribute to also prevent serde from generating an default implementation. (This too works for `deserialize`).

  If you use ufcs, please note that you might also need `alias serialize = serde.attrs.serialize;` to import the default overloads.

- `Skip`: skips an member field in (de)serialization.

- `SkipIf`: skips an member field in serialization only if any of the given functions return `true`.
            Can be used multiple times.
    ```d
    struct Test {
        /// This name is only serialized if the name is non-null AND not empty.
        @SerdeSkipIf(a => (a is null || a.length < 1))
        string name;
    }
    ```

- `With`: specifies a module path to use as lookup for custom `serialize` and `deserialize` functions to use.
    ```d
    module my.custom.mod;
    void serialize(ref string instance, Serializer ser) {}
    void deserialize(ref string instance, Deserializer de) {}

    module test;
    struct Test {
        /// Will be serialized with `my.custom.mod.serialize`,
        /// and deserialized with `my.custom.mod.deserialize`.
        @SerdeWith!(my.custom.mod)
        string name;
    }
    ```

- `SerializeWith`, `DeserializeWith`: Specifies custom functions for either serialization or deserialization.
    These attributes have a *higher* priority than the `With` attribute.
    ```d
    module test;

    void my_serialize(ref string instance, Serializer ser) {}
    void my_deserialize(ref string instance, Deserializer de) {}

    struct Test {
        @SerdeWith!(test.my_serialize)
        @SerdeWith!(test.my_deserialize)
        string name;
    }
    ```

- `Rename`: renames an member for (de)serialization. It comes in two forms:
  - `Serde.Rename("a")` this form sets the name for both serialization as well as deserialization to `"a"` and is a shorthand of `Serde.Rename("a", "a")`.
  - `Serde.Rename("b", "c")` this form gives you control over the name for both serialization and deserialization independently (in exactly that order).

    Due to a restriction of structs in dlang, both parameters need to be specified. If you dont need one, just set it to `null` or an empty string.

    For better readability, it is recommended to use dlang's ability for named parameters and write `Serde.Rename(serialize: "b", deserialize: "c")`instead.

- `Raw`: marks an member to used "as-is". This means that the value of the member is directly copied into the output, if the format supports it. Members need to be of type string or have an returntype of an string for this to work. Formats that supports this are JSON and Yaml.

- `Getter`: marks an member function to be used in serialization.

- `Setter`: marks an member function to be used in deserialization.

- `Alias`: specifies additional names for deserialization.

- `Optional`: marks an member as being optional, which will prevent deserialization from failing if the member was not deserialized.

- `DenyUnknownFields`: marks an struct or class to throw an error when encountering unknown fields in deserialization.
