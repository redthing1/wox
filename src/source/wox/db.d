module wox.db;

import std.stdio;
import std.file;
import std.path;
import std.conv;
import std.string;
import std.algorithm;
import std.array;
import wren;
import microrm;
import optional;

import wox.models;

struct RecipeCache {
    long id;
    string name;
    long hash;
}

enum WoxDatabaseSchema = buildSchema!(
        RecipeCache,
    );

class WoxDatabase {
    MDatabase db;

    this(string database_file) {
        db = new MDatabase(".wox.db");
        db.run(WoxDatabaseSchema);
    }

    void update_recipe_cache(string recipe_name, long hash) {
        // writeln("Updating recipe cache for ", recipe_name, " with hash ", hash);
        auto existing_entry = get_recipe_cache(recipe_name);
        if (!existing_entry.empty) { // update
            db.insertOrReplace(RecipeCache(existing_entry.front.id, recipe_name, hash));
        } else { // insert new
            db.insert(RecipeCache(0, recipe_name, hash));
        }
    }

    Optional!RecipeCache get_recipe_cache(string recipe_name) {
        auto recipe_cache = db.select!RecipeCache.where("name = ", recipe_name).run;
        if (recipe_cache.empty) {
            return no!RecipeCache;
        }
        return some(recipe_cache.front);
    }
}
