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
 * Module to hold the attributes used to supply an default implementation for
 * serialization and deserialization of struct's and classes.
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2024 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/mai-lapyst, Mai-Lapyst)
 */
module serde.attrs;

import std.traits : hasUDA, getUDAs;

struct Serde {
    /// Attribute to denote that an `serialize` and `unserialize` function exists via ufcs.
    enum UseUfcs;

    /// Checks if the given element `T` has the `Serde.UseUfcs` attribute present.
    enum isUfcs(alias T) = hasUDA!(T, UseUfcs);

    /// Attribute to mark an member as to be skipped in both (de)serialization.
    /// 
    /// Can also be added to an type (class or struct) to skip the whole
    /// type for (de)serialization
    enum Skip;

    /// Checks if the given element `T` has the `Serde.Skip` attribute present.
    enum isSkipped(alias T) = hasUDA!(T, Skip);

    /// Attribute to mark an member to be renamed.
    /// If given one string, it is used for both serialization and deserialization.
    /// 
    /// Example:
    /// ```d
    /// struct Obj {
    ///   @(Serde.Rename("j"))
    ///   int i = 12;
    /// 
    ///   @(Serde.Rename(serialize: "k", deserialize: "z"))
    ///   int o = 34;
    /// }
    /// 
    /// void main() {
    ///    auto s = Obj().toJson(); // returns "{\"j\":12,\"k\":34}"
    /// }
    /// ```
    static struct Rename {
        string serialize, deserialize;

        @disable this();

        this(string name) {
            this.serialize = name;
            this.deserialize = name;
        }

        this(string serialize, string deserialize) {
            this.serialize = serialize;
            this.deserialize = deserialize;
        }
    }

    /// Retrieves the name for an given item / member `I`,
    /// by looking for an `Serde.Rename` attribute.
    /// 
    /// The `isSerialization` parameter specifies if the name is to be used
    /// for serialization; if it is `true`, then the field `serialize` of
    /// `Serde.Rename` is used. Otherwise the `deserialize` field will be used.
    /// 
    /// If no attribute could be found (or the name retrieved is either `null` or
    /// empty), the `fallback` is used.
    template getNameFromItem(alias I, string fallback, bool isSerialization)
    {
        static if (hasUDA!(I, Rename)) {
            alias udas = getUDAs!(I, Rename);
            static assert (udas.length > 0, "Cannot have more than one @Serde.Rename attribute on an element");
            static if (isSerialization) {
                enum name = udas[0].serialize;
            } else {
                enum name = udas[0].deserialize;
            }
            import std.string : empty;
            static if (name !is null && !name.empty) {
                enum getNameFromItem = name;
            } else {
                enum getNameFromItem = fallback;
            }
        } else {
            enum getNameFromItem = fallback;
        }
    }

    /// Marks an member to be used "as-is"; requires the type of the member / return type
    /// to be a string.
    enum Raw;

    /// Checks if the given element `T` has the `Serde.Raw` attribute present.
    enum isRaw(alias T) = hasUDA!(T, Raw);

    /// Marks an member function to be used in serialization. By default the name of the
    /// function is used as-is.
    enum Getter;

    /// Checks if the given element `T` has the `Serde.Getter` attribute present.
    enum isGetter(alias T) = hasUDA!(T, Getter);
}

/*
 * Convinience aliases to allow for `@SerdeRename("a")` instead of `@(Serde.Rename("a"))`.
 */

alias SerdeUseUfcs = Serde.UseUfcs;
alias SerdeSkip = Serde.Skip;
alias SerdeRename = Serde.Rename;
alias SerdeRaw = Serde.Raw;
alias SerdeGetter = Serde.Getter;
