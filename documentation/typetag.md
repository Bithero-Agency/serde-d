# Typetagging

The serde-d framework comes with an ability to deserialize `interface`s and `abstract class`es: `serde.typetag`.

It provides multiple forms how an class can be serialized. Which all consist of marking an "base" instance & which form to use and then marking / registering all "extends".

## Registering an extend

To register an extend / concrete instance, you just need to use the `RegisterTypetag` template as a mixin *inside* your class:

```d
class BasicAuth : Auth {
    // ...
    
    mixin RegisterTypetag!(Auth, "basic");
}
```

The mixin accepts as first argument the "base"-type you want to register yourself to, and after that the name it should be registerd as.

This allows not only to register aliases for the same base-type very easily, but also to register to mutliple bases, which is important if your class implements multiple interfaces.

## Internal tag

The internal tag puts the tag with all the other attributes of an struct:

```d
import std.stdio;
import serde.json;
import serde.typetag;

interface Auth {
    mixin TypetagInternal!("type");
}

class BasicAuth : Auth {
    string user;
    this(string user) { this.user = user; }

    mixin RegisterTypetag!(Auth, "basic");
}

void main() {
    Auth a = new BasicAuth("foo");
    writeln( a.toJson );

    auto a = fromJson!Auth( a.toJson );
    assert(cast(BasicAuth) a !is null);
}
```

```json
{
    "type": "basic", // this is the tag!
    "user": "foo",
    // ...
}
```

The `TypetagInternal` template accepts an tag argument, which can be used to configure the name of the key used as a tag.

> Note: The tag doesn't need to be the first key either; all keys before it are read as a `AnyValue` (`read_any`) and savely stored away until the correct deserialization target could be found.

## External tag

The internal tag puts the tag as a key and the instance as the value of said key:

```d
import std.stdio;
import serde.json;
import serde.typetag;

interface Auth {
    mixin TypetagExternal!();
}

class BasicAuth : Auth {
    string user;
    this(string user) { this.user = user; }

    mixin RegisterTypetag!(Auth, "basic");
}

void main() {
    Auth a = new BasicAuth("foo");
    writeln( a.toJson );

    auto a = fromJson!Auth( a.toJson );
    assert(cast(BasicAuth) a !is null);
}
```

```json
{
    // this is the tag!
    "basic": {
        "user": "foo",
        // ...
    },
}
```

> Note: The tag-instance pair is the only thing allowed inside the map; no other keys before or after it are allowed.

## Adjacent tag

The adjacently tagged format puts the tag and value inside seperate keys:

```d
import std.stdio;
import serde.json;
import serde.typetag;

interface Auth {
    mixin TypetagAdjacent!("type", "value");
}

class BasicAuth : Auth {
    string user;
    this(string user) { this.user = user; }

    mixin RegisterTypetag!(Auth, "basic");
}

void main() {
    Auth a = new BasicAuth("foo");
    writeln( a.toJson );

    auto a = fromJson!Auth( a.toJson );
    assert(cast(BasicAuth) a !is null);
}
```

```json
{
    // this is the tag!
    "type": "basic",
    // this is the value!
    "value": {
        "user": "foo",
        // ...
    },
}
```

> Note: The order in which the tag and the value are parsed is irrelevant, they only need to be the only keys inside the map.
