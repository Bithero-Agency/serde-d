# Types

The framework works by defining an internal data schema that all types are converted into before makeing their way to the actual serializer. These types are:

- "basic" scalar types, which need to match the `std.traits.isScalar` template. By default this should be:
  - `bool`,
  - `ubyte`, `ushort`, `uint`, `ulong`,
  - `byte`, `short`, `int`, `long`,
  - `float`, `double`, `real`,
  - `char`, `wchar`, `dchar`

- string types, which need to match the `std.traits.isSomeString` template, which gives you:
  - `const(char)[]` / `string`
  - `const(wchar)[]` / `wstring`
  - `const(dchar)[]` / `dstring`

- An internal-use-only `RawValue` struct, which is used under the hood for the `Serde.Raw` attribute.

- "enums", which are dlang's `enum` type.

- A "sequence", which is an arbitary length list of values where the length might or might not be known beforehand. Typically all elements have the same type. However, this is implementation defined.

  By default these types are converted to it:
  - `T[]` any array, be it dynamic or staticly sized
  - `std.container.DList`
  - `std.container.SList`
  - An input range that must match the `std.range.primitives.isInputRange` template; which optionally is allowed to match `std.range.primitives.hasLength`. Note that all strings (`std.traits.isSomeString`) are excluded from this.

- A "tuple", which is an fixed-length list of values, where typically all elements can be of different type. By default only the libphobos type `std.typecons.Tuple` is converted to it automatically.

- A "map", which is a set of key-value pairs where the length might or might not be known beforehand. Typically the entires have the same type (that means the key and the value type are the same between them). However, this is implementation defined.

- A "struct", which is any user-defined type (means `struct` and `class` in dlang).
