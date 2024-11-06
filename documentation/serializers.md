## Serializers

Each of the types the framework defines is mapped to one specific set of methods that are responsible to write the types in the underlaying format the serializer supports. Those are:

- "basic" values: They're written by the `write_basic(T)(T value)` method.

- "string" values: They're written by the `write_string(T)(scope T str)` method.

- `RawValue`: They're written by the `write_raw(RawValue v)` method.

- "enum" values: They're written by the `write_enum(T)(T value)` method.

  There are helpers in `serde.common` to help with looking up the index (`getEnumKeyIndex`) and/or name (`getEnumKeyName`) of an enum instance value.

- "sequences":

  They're written by first starting an sequence with `Seq start_seq(T)()` (or `Seq start_seq(T)(ulong length)` for if the length is known in advance). It is implementation defined what the serializer does with the `T` parameter, which represents the element type of the list. If you dont know the element type in advance, use `void` for `T`.

  After that, you can use the returned value that implements `Serializer.Seq` to write as many elements as you like by calling `write_element(T)(T e)`.

  If you're finished, call `end()` on the returned value to finish off the sequence. Note that this is **not** done automatically when the value leaves the scope as it heap-allocated type in most cases and cannot be dropped with certainty implicitly at the end of an scope.

- "tuples":

  They're written by first starting an tuple with `Tuple start_tuple(Elements...)()`, where the `Elements` template vararg parameter is an type-tuple with all the types of the tuple in order. For the libphobos type this is the `.Types` member. It's not defined what or if an implementation uses these informations, but it must be given to it when the function is called.

  After that, you can use the returned value that implements `Serializer.Tuple` to write as many elements as you like by calling `write_element(T)(T e)`.

  And like with sequences, you'll need to finish it off with an call to `end()`; the same note about dropping is applied here as well.

- "maps":

  By default only associative arrays (`V[K]`) types are converted to it.

  They're written by first starting an map with `Map start_map(K,V)()` (or `Seq start_map(K,V)(ulong length)` for if the length is known in advance). It is implementation defined what the serializer does with the `K` and `V` parameters, which represents the key type and value type of the map respectively. If you dont know one or both of them in advance, use `void` for them.

  After that, you can use the returned value that implements `Serializer.Map` to write as many entires as you like by calling `write_key(K)(K key)` immedeately followed by a call to `write_value(V)(V value)`.

  And like with sequences or tuples, you'll need to finish it off with an call to `end()`; the same note about dropping is applied here as well.

- "structs":

  They're written by first starting an struct with `Struct start_struct(T)()`. It is implementation defined what the serializer does with the `T` parameter, which represents the struct or class type. It **must** be supplied when calling the function and **cannot** be supplied with `void` or anything that isnt a `struct` or `class`.

  After that, you can use the returned value that implements `Serializer.Struct` to write as many fields as you like by calling `write_field(T)(string name, T value)`.

  And like with sequences, tuples or maps, you'll need to finish it off with an call to `end()`; the same note about dropping is applied here as well.
