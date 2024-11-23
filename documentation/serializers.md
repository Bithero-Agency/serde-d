## Serializers

Each of the types the framework defines is mapped to one specific set of methods that are responsible to write the types in the underlaying format the serializer supports. Those are:

- "boolean" values: They're written by the `write_bool(bool value)` method.

- "unsigned" values: They're written by the `write_unsigned(ulong value, ubyte sz)` method.
  The `sz` gives an hint about the (byte) size of the unsigned value:
  - `ubyte` is `1`
  - `ushort` is `2`
  - `uint` is `4`
  - `ulong` is `8`

- "signed" values: They're written by the `write_signed(long value, ubyte sz)` method.
  The `sz` gives an hint about the (byte) size of the signed value:
  - `byte` is `1`
  - `short` is `2`
  - `int` is `4`
  - `long` is `8`

- "floating-point" values: They're written by the `write_float(double value, ubyte sz)` method.
  The `sz` gives an hint about the (byte) size of the floating-point value:
  - `float` is `4`
  - `double` is `8`

- "real" values: They're written by the `write_real(real value)` method.

- "character" values: They're written by the `write_char(dchar value)` method.

- "string" values: They're written by the `write_string(string str)` method.

- `RawValue`: They're written by the `write_raw(RawValue v)` method.

- "enum" values: They're written by the `write_enum(string name, ulong index)` method.
  The given `name` is equivalent to the name of the enum's variant (i.e. `Earth` in `enum Planet { Earth, Mars, Jupiter }`), and the `index` of the index into the enum if it where an array (i.e. `2` for `Mars` in the previous example).

- "sequences":

  They're written by first starting an sequence with `Seq start_seq()` (or `Seq start_seq(ulong length)` for if the length is known in advance).

  After that, you can use the returned value that implements `Serializer.Seq` to write as many elements as you like by calling `Serializer write_element()`.
  The returned serializer MUST be used to write **exactly** one value, preferbly by using `.serialize()`.

  If you're finished, call `end()` on the returned value to finish off the sequence. Note that this is **not** done automatically when the value leaves the scope as it heap-allocated type in most cases and cannot be dropped with certainty implicitly at the end of an scope.

- "tuples":

  They're written by first starting an tuple with `Tuple start_tuple()`.

  After that, you can use the returned value that implements `Serializer.Tuple` to write as many elements as you like by calling `Serializer write_element()`.
  The returned serializer MUST be used to write **exactly** one value, preferbly by using `.serialize()`.

  And like with sequences, you'll need to finish it off with an call to `end()`; the same note about dropping is applied here as well.

- "maps":

  By default only associative arrays (`V[K]`) types are converted to it.

  They're written by first starting an map with `Map start_map()` (or `Seq start_map(ulong length)` for if the length is known in advance).

  After that, you can use the returned value that implements `Serializer.Map` to write as many entires as you like by first calling `Serializer write_key()` and writing the key to the returned serializer. Like before, this **must** be done, and only **exactly one** value, preferbly by using `.serialize()`.
  
  After that, follow up immediately with a call to `Serializer write_value()`, writing the value to the returned serializer. The same notes as before apply.

  And like with sequences or tuples, you'll need to finish it off with an call to `end()`; the same note about dropping is applied here as well.

- "structs":

  They're written by first starting an struct with `Struct start_struct()`. It is implementation defined what the serializer does with the `T` parameter, which represents the struct or class type. It **must** be supplied when calling the function and **cannot** be supplied with `void` or anything that isnt a `struct` or `class`.

  After that, you can use the returned value that implements `Serializer.Struct` to write as many fields as you like by calling `Serializer write_field(string name)`. Like before, use the returned serializer to write the field's value.

  And like with sequences, tuples or maps, you'll need to finish it off with an call to `end()`; the same note about dropping is applied here as well.
