## Deserializers

Each of the types the framework defines is mapped to one specific set of methods that are responsible to read the types from the underlaying format the deserializer supports. Those are:

- "boolean" values: They're read by the `read_bool(ref bool value)` method.

- "unsigned" values: They're read by the `read_unsigned(ref ulong value, ubyte sz)` method.
  The `sz` gives an hint about the (byte) size of the unsigned value:
  - `ubyte` is `1`
  - `ushort` is `2`
  - `uint` is `4`
  - `ulong` is `8`

- "signed" values: They're read by the `read_signed(ref long value, ubyte sz)` method.
  The `sz` gives an hint about the (byte) size of the signed value:
  - `byte` is `1`
  - `short` is `2`
  - `int` is `4`
  - `long` is `8`

- "floating-point" values: They're read by the `read_float(ref double value, ubyte sz)` method.
  The `sz` gives an hint about the (byte) size of the floating-point value:
  - `float` is `4`
  - `double` is `8`

- "real" values: They're read by the `read_real(ref real value)` method.

- "character" values: They're read by the `read_char(ref dchar value)` method.

- "string" values: They're read by the `read_string(ref string str)` method.

- "enum" values: They're read by the `read_enum(ref AnyValue value)` method.
  The default enum deserializer expects to retrieve either a string or an integer inside the provided `AnyValue`.

- `read_ignore()` is a special method to ignore one value from the input. This is really just a specialized `read_any()` variant for when the value is not needed.

- `read_any(ref AnyValue value)` reads any one value from the input. While `AnyValue` can hold nearly any type, it **must** only be basic types (bool, integers, floats, real, character) and strings. For "complex" types like sequences, please use an `AnyValue[]`, and for mappings use `AnyMap`.

- "sequences":

    They're read by first acquiring an `SeqAccess` from `read_seq()`, this instance is used for all further calls.

    After that, you can (optionally), call `size_hint()` on it to recieve an `Nullable!ulong`, which (if set) specifies how many elements are expected. You can use this for example to reserve enough memory before reading all elements.

    You then can read elements by repeatedly calling `Deserializer read_element()`, until it returns `null`. If the return value is not-`null`, it's an deserializer that **must** be used to read an value from it.

    After no more elements can be read, call `end()`.

- "tuples":

    They work in the same way as sequences, but start instead with `SeqAccess read_tuple()`. Otherwise they're the same.

- "maps":

    They're read by first acquiring an `MapAccess` from `read_map()`, this instance is used for all further calls.

    You now need to call `bool read_key(ref AnyValue value)`, if the method returns `true` all is okay; if instead `false` is returned, no more key's are present in the input.

    If an key was successfully read, it is put into the specified `AnyValue` variable. You now can either read the value by calling `Deserializer read_value()`, which is an deserializer that **must** be used to read the value, or you can call `void ignore_value()`, to entriely skip the value.

    After all keys are processed, call `end()`.

- "structs":

    They work in the same way as sequences, but start instead with `SeqAccess read_struct()`. This method is allowed to also return `null` which indicate an `null` value.

    The `ignore_value()` method is especially helpfull when dealing with structs as you can skip entire values for keys that doesn't correspond to any field in your struct.

### Custom deserialization

It is possible to provide custom deserialization-code for user-defined types like `struct`'s and `class`'es.

To do this, there are two methods that are called by the framework:

- `void deserialize(Deserializer de);` and

- `static void deserializeInstance(ref typeof(this) instance, Deserializer de);`

> Note: The automatic deserialize method provided by the framework is only available if none of the above could be found inside the class / struct.
