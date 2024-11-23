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

> Note: for more infromation how to paragmatically use the serializer, see `documentation/types.md` and `documentation/serializers.md`.

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

- `Rename`: renames an member for (de)serialization. It comes in two forms:
  - `Serde.Rename("a")` this form sets the name for both serialization as well as deserialization to `"a"` and is a shorthand of `Serde.Rename("a", "a")`.
  - `Serde.Rename("b", "c")` this form gives you control over the name for both serialization and deserialization independently (in exactly that order).

    Due to a restriction of structs in dlang, both parameters need to be specified. If you dont need one, just set it to `null` or an empty string.

    For better readability, it is recommended to use dlang's ability for named parameters and write `Serde.Rename(serialize: "b", deserialize: "c")`instead.

- `Raw`: marks an member to used "as-is". This means that the value of the member is directly copied into the output, if the format supports it. Members need to be of type string or have an returntype of an string for this to work. Formats that supports this are JSON and Yaml.

- `Getter`: marks an member function to be used in serialization.