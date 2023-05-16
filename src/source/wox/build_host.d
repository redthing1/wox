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

    struct Options {
        string graphviz_file = null;
    }

    Options options;

    this(Logger log, Options options) {
        this.log = log;
        this.options = options;
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
            log.trace(" finding recipe to build footprint %s", footprint);
            foreach (recipe; all_recipes) {
                // log.trace("  checking if recipe '%s' can build footprint %s", recipe.name, footprint);
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

        struct RecipeWalk {
            Recipe recipe;
            Nullable!Recipe parent_recipe;
            SolverNode[] parent_nodes;
        }

        struct Edge {
            SolverNode from;
            SolverNode to;
        }

        auto recipe_queue = DList!RecipeWalk();
        bool[RecipeWalk] visited_walks;
        SolverNode[Footprint] nodes_for_footprints;

        foreach (recipe; goal_recipes) {
            log.trace(" adding target recipe to solver graph: %s", recipe);
            recipe_queue.insertBack(RecipeWalk(recipe, Nullable!Recipe.init, []));
        }

        while (!recipe_queue.empty) {
            auto walk = recipe_queue.front;
            recipe_queue.removeFront;

            visited_walks[walk] = true;

            // process this walk
            log.trace("processing recipe '%s'", walk.recipe.name);

            // add graph nodes for the outputs
            SolverNode[] curr_nodes;
            foreach (output; walk.recipe.outputs) {
                // log.trace("  adding node for output %s", output);
                // auto output_node = new SolverNode(output);

                // see if a node for this output already exists
                SolverNode output_node = null;
                if (output in nodes_for_footprints) {
                    // use existing node
                    output_node = nodes_for_footprints[output];
                    log.trace("  using node for output %s", output);
                } else {
                    // create a new node for this output
                    output_node = new SolverNode(output);
                    log.trace("  created node for output %s", output);
                    nodes_for_footprints[output] = output_node;
                }

                // add this node to my parent's children
                if (!walk.parent_recipe.isNull) {
                    // since we are the child, our input is the parent's outputs
                    // so add this node to the parent node's children
                    foreach (parent_node; walk.parent_nodes) {
                        parent_node.children ~= output_node;
                        log.trace("   added edge %s -> %s", parent_node, output_node);
                    }
                } else {
                    // if the parent is null, this is a root node
                    graph.roots ~= output_node;
                }

                curr_nodes ~= output_node;
            }

            // add dependencies to the queue (from our inputs)
            foreach (dep; get_dependencies(walk.recipe)) {
                // first, check if the footprint is a file that exists
                if (dep.reality == Footprint.Reality.File && std.file.exists(dep.name)) {
                    log.trace("  using file %s", dep);
                    // this is a real file, which is a terminal
                    continue;
                }
                // find a recipe that can build this dependency
                auto dep_recipe = find_recipe_to_build(dep);
                auto dep_walk = RecipeWalk(dep_recipe, Nullable!Recipe(walk.recipe), curr_nodes);

                if (dep_walk in visited_walks) {
                    // we've already visited this walk, so we don't need to add it to the queue
                    log.dbg("  already visited dependency walk %s", dep_walk);

                    continue;
                }

                // add it to the queue
                recipe_queue.insertBack(dep_walk);
            }
        }

        // now it should be a real graph
        if (options.graphviz_file !is null) {
            dump_solver_graph(graph, options.graphviz_file);
        }

        return true;
    }

    void dump_solver_graph(SolverGraph graph, string filename) {
        log.trace("dumping solver graph to %s", filename);

        auto gv_builder = appender!string;

        gv_builder ~= "digraph {\n";

        // dfs through the graph and add nodes to the graphviz graph
        bool[SolverNode] visited_nodes;
        auto node_stack = DList!SolverNode();

        // queue initial nodes
        foreach (node; graph.roots) {
            // log.trace(" gv root %s", node);
            node_stack.insertBack(node);
        }

        while (!node_stack.empty) {
            auto node = node_stack.front;
            node_stack.removeFront;

            visited_nodes[node] = true;

            // add this node to the graph
            // log.trace(" gv node %s", node);
            auto reality = node.data.reality;
            auto node_style = ["shape": "box"];
            switch (reality) {
            case Footprint.Reality.File:
                node_style["color"] = "green";
                break;
            case Footprint.Reality.Virtual:
                node_style["color"] = "blue";
                break;
            case Footprint.Reality.Unknown:
                node_style["color"] = "red";
                break;
            default:
                assert(0);
            }
            // gv.node(node, node_style);
            gv_builder ~= format("  \"%s\" [shape=box,color=%s];\n", node, node_style["color"]);

            // add this node's children to the queue
            foreach (child; node.children) {
                if (child in visited_nodes) {
                    continue;
                }

                // this is a child, add an edge then queue it
                // log.trace("  gv edge %s -> %s", node, child);
                // gv.edge(node, child, ["style": "solid"]);
                gv_builder ~= format("  \"%s\" -> \"%s\" [style=solid];\n", node, child);
                node_stack.insertBack(child);
            }
        }

        gv_builder ~= "}\n";

        // gv.save(filename);
        std.file.write(filename, gv_builder.data);
    }
}
