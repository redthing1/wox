module wox.build_host;

import std.stdio;
import std.file;
import std.path;
import std.conv;
import std.string;
import std.algorithm;
import std.array;
import core.stdc.stdio;
import core.stdc.string;
import std.exception : enforce;
import std.typecons;
import std.container.dlist;
import wren;

import wox.log;
import wox.models;
import wox.wren_integration;
import wox.foreign.binder;
import wox.wren_utils;
import wox.solver;

class BuildHost {
    static Logger log;

    this(Logger log) {
        this.log = log;
    }

    extern (C) static void wren_write(WrenVM* vm, const(char)* text) {
        writef("%s", text.to!string);
    }

    extern (C) static void wren_error(
        WrenVM* vm, WrenErrorType errorType, const(char)* module_, int line, const(char)* msg
    ) {
        switch (errorType) with (WrenErrorType) {
        case WREN_ERROR_COMPILE: {
                log.err("[wren] Error in %s at line %d: %s", module_.to!string, line, msg
                        .to!string);
                break;
            }
        case WREN_ERROR_STACK_TRACE: {
                log.err("[wren] Error in %s at line %d: %s", module_.to!string, line, msg
                        .to!string);
                break;
            }
        case WREN_ERROR_RUNTIME: {
                log.err("[wren] Runtime Error: %s", msg.to!string);
                break;
            }
        default: {
                log.err("[wren] Unknown Error: %s", msg.to!string);
                break;
            }
        }
    }

    bool build(string buildscript, string[] requested_targets, string cwd, string[] args, string[string] env) {
        log.trace("buildscript:\n%s", buildscript);

        // vm info
        auto wren_ver = wrenGetVersionNumber();
        log.trace("wren version: %s", wren_ver);

        // set up vm
        WrenConfiguration config;
        wrenInitConfiguration(&config);

        // output functions
        config.writeFn = &wren_write;
        config.errorFn = &wren_error;

        // bind foreign functions
        WoxBuildForeignBinder.initialize(WoxForeignContext(log, cwd, args, env));
        config.bindForeignMethodFn = &WoxBuildForeignBinder.bindForeignMethod;

        // create vm
        WrenVM* vm = wrenNewVM(&config);

        // create the wox module
        log.trace("loading wox module");
        auto wox_run_result = wrenInterpret(vm, WOX_MODULE.toStringz, WOX_SCRIPT.toStringz);
        if (wox_run_result != WREN_RESULT_SUCCESS) {
            log.err("failed to load wox module");
            return false;
        }

        // run buildscript module
        auto buildscript_run_result = wrenInterpret(vm, BUILDSCRIPT_MODULE.toStringz, buildscript
                .toStringz);
        if (buildscript_run_result != WREN_RESULT_SUCCESS) {
            log.err("failed to run buildscript module");
            return false;
        }

        // ensure enough slots for what we're going to do
        wrenEnsureSlots(vm, 2);
        // get the Build static class that should have been declared in the buildscript
        auto build_decl_slot = 0;
        wrenGetVariable(vm, BUILDSCRIPT_MODULE.toStringz, "Build", build_decl_slot);
        auto build_class_h = wrenGetSlotHandle(vm, build_decl_slot);
        if (build_class_h == null) {
            log.err("failed to get build instance handle from %s", BUILDSCRIPT_MODULE);
            return false;
        }

        // get the data exposed by the Build declaration
        // call Build.default_recipe static getter
        wrenSetSlotHandle(vm, 0, build_class_h);
        auto default_recipe_call_h = wrenMakeCallHandle(vm, "default_recipe");
        auto default_recipe_call_result = wrenCall(vm, default_recipe_call_h);
        if (default_recipe_call_result != WREN_RESULT_SUCCESS) {
            log.err("failed to call Build.default_recipe: %s", default_recipe_call_result);
            return false;
        }
        // get handle to the default recipe (recipe object)
        auto default_recipe_h = wrenGetSlotHandle(vm, 0);
        auto default_recipe_type = wrenGetSlotType(vm, 0);
        enforce(default_recipe_type == WREN_TYPE_UNKNOWN, "default recipe is not an object");

        // call Build.recipes static getter to get the list of all recipes
        wrenSetSlotHandle(vm, 0, build_class_h);
        auto recipes_call_h = wrenMakeCallHandle(vm, "recipes");
        auto recipes_call_result = wrenCall(vm, recipes_call_h);
        if (recipes_call_result != WREN_RESULT_SUCCESS) {
            log.err("failed to call Build.recipes: %s", recipes_call_result);
            return false;
        }
        // slot 0 contains a list of recipe objects
        auto all_recipes_h = WrenUtils.wren_read_handle_list(vm, 0, 1);

        auto default_recipe = ModelsFromWren.convert_recipe_from_wren(vm, default_recipe_h);
        auto all_recipes = all_recipes_h
            .map!(x => ModelsFromWren.convert_recipe_from_wren(vm, x)).array;

        foreach (recipe; all_recipes) {
            log.trace("recipe:\n%s", recipe);
        }

        // make a list of recipes we want to build
        // if any targets are specified, we use those
        // but we have to ensure that we have recipes that know how to build them
        // if no targets are specified, we use the default recipe
        Recipe[] candidate_recipes;

        if (requested_targets.length > 0) {
            // ensure we have recipes for all the targets
            foreach (target; requested_targets) {
                log.trace("looking for recipe that can build target %s", target);
                bool candidate_found = false;
                foreach (recipe; all_recipes) {
                    if (recipe.can_build_target(target)) {
                        log.trace("found recipe that can build target %s: %s", target, recipe);
                        candidate_recipes ~= recipe;
                        candidate_found = true;
                    }
                }

                if (!candidate_found) {
                    log.err("no recipe found that can build target %s", target);
                    return false;
                }
            }
        } else {
            // no targets were specifically requested, so we use the default recipe
            log.trace("using default recipe: %s", default_recipe);
            candidate_recipes = [default_recipe];
        }

        // attempt to resolve the recipes, because some still have footprints with unknown realities
        resolve_recipes(all_recipes);

        // dump resolved recipes
        foreach (recipe; all_recipes) {
            log.trace("resolved recipe:\n%s", recipe);
        }

        // build the recipes
        auto result = build_recipes(candidate_recipes, all_recipes);

        return result;
    }

    void resolve_recipes(Recipe[] recipes) {
        log.trace("resolving recipes");

        void ensure_footprint_reality(Footprint* fp) {
            // if it's of unknown reality, try to resolve it
            if (fp.reality == Footprint.Reality.Unknown) {
                log.trace("  resolving %s", *fp);
                // unknown reality means we don't know if it's a file or virtual
                // so we check if it's a file using some heuristics

                if (std.file.exists(fp.name)) { // is it a real file?
                    fp.reality = Footprint.Reality.File;
                    log.trace("   %s is a file", *fp);
                } else if (fp.name.startsWith(".")) { // is it a relative path?
                    fp.reality = Footprint.Reality.File;
                    log.trace("   %s is probably a file", *fp);
                } else if (fp.name.canFind("/") || fp.name.canFind(".")) { // is it a path?
                    fp.reality = Footprint.Reality.File;
                    log.trace("   %s is probably a file", *fp);
                } else {
                    fp.reality = Footprint.Reality.Virtual;
                    log.trace("   assuming %s is virtual", *fp);
                }
            }
        }

        foreach (recipe; recipes) {
            log.trace(" resolving recipe '%s'", recipe.name);
            for (auto i = 0; i < recipe.inputs.length; i++) {
                auto input = &recipe.inputs[i];
                ensure_footprint_reality(input);
            }
            for (auto i = 0; i < recipe.outputs.length; i++) {
                auto output = &recipe.outputs[i];
                ensure_footprint_reality(output);
            }
        }
    }

    bool build_recipes(Recipe[] goal_recipes, Recipe[] all_recipes) {
        // create a solver graph
        log.trace("creating solver graph");
        auto graph = new SolverGraph();

        Recipe find_recipe_to_build(Footprint footprint) {
            // find a recipe that says it can build this footprint
            foreach (recipe; all_recipes) {
                log.trace("  checking if recipe '%s' can build footprint %s", recipe.name, footprint);
                if (recipe.can_build_footprint(footprint)) {
                    log.trace("   recipe '%s' can build footprint %s", recipe.name, footprint);
                    return recipe;
                }
            }
            enforce(false, format("no recipe found that can build footprint %s", footprint));
            assert(0);
        }

        Footprint[] get_dependencies(Recipe recipe) {
            // get the immediate dependencies of this recipe
            return recipe.inputs;
        }

        log.trace(" adding target recipes to solver graph");

        auto recipe_queue = DList!Recipe();
        bool[Recipe] visited_recipes;

        foreach (recipe; goal_recipes) {
            recipe_queue.insertBack(recipe);
        }

        while (!recipe_queue.empty) {
            auto recipe = recipe_queue.front;
            recipe_queue.removeFront;

            visited_recipes[recipe] = true;

            // process this recipe
            log.trace("processing recipe '%s'", recipe.name);

            // add dependencies to the queue
            foreach (dep; get_dependencies(recipe)) {
                // first, check if the footprint is a file that exists
                if (dep.reality == Footprint.Reality.File && std.file.exists(dep.name)) {
                    log.trace("  using file %s", dep);
                    // this is a real file, which is a terminal
                    continue;
                }
                // find a recipe that can build this dependency
                auto dep_recipe = find_recipe_to_build(dep);

                if (dep_recipe in visited_recipes) {
                    // we've already visited this recipe, so we don't need to add it to the queue
                    log.dbg("  already visited dependency recipe '%s'", dep_recipe.name);
                    continue;
                }

                // add it to the queue
                recipe_queue.insertBack(dep_recipe);
            }
        }

        return true;
    }
}
