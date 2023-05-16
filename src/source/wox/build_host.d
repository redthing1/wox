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
import std.parallelism;
import std.algorithm;
import core.atomic;
import wren;
import miniorm;
import optional;

import wox.log;
import wox.models;
import wox.wren_integration;
import wox.foreign.binder;
import wox.wren_utils;
import wox.solver;
import wox.db;

class BuildHost {
    static Logger log;

    struct Options {
        int n_jobs = 1;
        string graphviz_file = null;
        bool enable_cache = false;
    }

    Options options;
    WoxDatabase db;

    this(Logger log, Options options) {
        this.log = log;
        this.options = options;

        // if cache is enabled, open the database
        if (options.enable_cache) {
            db = new WoxDatabase(".wox.db");
        }
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

    extern (C) static WrenLoadModuleResult wren_load_module(WrenVM* vm, const(char)* name) {
        log.trace("loading module %s", name.to!string);
        auto module_base_path = name.to!string.replace(".", "/");
        static immutable possible_extensions = ["", ".wren", ".wox"];
        // find a matching file
        auto module_path = possible_extensions.map!(ext => module_base_path ~ ext)
            .find!(p => std.file.exists(p));
        if (module_path.empty) {
            // log.err("failed to find module %s", name.to!string);
            return WrenLoadModuleResult(null);
        }
        auto module_source = std.file.readText(module_path.front);

        return WrenLoadModuleResult(module_source.toStringz);
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

        // import handler
        config.loadModuleFn = &wren_load_module;

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
        enforce(wrenGetSlotType(vm, 0) == WREN_TYPE_STRING, "default recipe is not a string");
        auto default_recipe_name = wrenGetSlotString(vm, 0).to!string;

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

        auto all_recipes = all_recipes_h
            .map!(x => ModelsFromWren.convert_recipe_from_wren(vm, x)).array;
        // find the default recipe in the list
        auto maybe_default_recipe = all_recipes.filter!(x => x.name == default_recipe_name);
        if (maybe_default_recipe.empty) {
            log.err("specified default recipe %s not found", default_recipe_name);
            return false;
        }
        auto default_recipe = maybe_default_recipe.front;

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
                log.trace("looking for recipe matching requested target %s", target);
                bool candidate_found = false;
                foreach (recipe; all_recipes) {
                    if (recipe.can_build_target(target)) {
                        log.trace("found recipe for requested target %s: %s", target, recipe);
                        candidate_recipes ~= recipe;
                        candidate_found = true;
                    }
                }

                if (!candidate_found) {
                    log.err("no recipe found for requested target %s", target);
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

        // foreach (recipe; recipes) {
        for (auto recipe_ix = 0; recipe_ix < recipes.length; recipe_ix++) {
            auto recipe = &recipes[recipe_ix];

            log.trace(" resolving recipe '%s'", recipe.name);
            for (auto i = 0; i < recipe.inputs.length; i++) {
                auto input = &recipe.inputs[i];
                ensure_footprint_reality(input);
            }
            for (auto i = 0; i < recipe.outputs.length; i++) {
                auto output = &recipe.outputs[i];
                ensure_footprint_reality(output);
            }

            // remove any virtual footprints if we already have a file footprint for the same name
            auto file_outputs = recipe.outputs
                .filter!(x => x.reality == Footprint.Reality.File).array;
            auto deduplicated_virtual_outputs = recipe.outputs
                .filter!(x => x.reality == Footprint.Reality.Virtual)
                .filter!(x => !file_outputs.any!(y => y.name == x.name))
                .array;

            recipe.outputs = file_outputs ~ deduplicated_virtual_outputs;
            // log.trace("  recipe '%s' new outputs: %s", recipe.name, recipe.outputs);
        }
    }

    bool build_recipes(Recipe[] goal_recipes, Recipe[] all_recipes) {
        auto solver_graph = build_solver_graph(goal_recipes, all_recipes);
        auto raw_toposorted_nodes = toposort_solver_graph(solver_graph);

        auto toposorted_queue = raw_toposorted_nodes.reverse;

        // now, we have a list of nodes
        // they are ordered with the top-level targets first, so we can work backwards

        auto use_single_thread = options.n_jobs == 1;
        // auto task_pool = new TaskPool(options.n_jobs);
        // task_pool.isDaemon = true;
        TaskPool make_task_pool() {
            auto task_pool = new TaskPool(options.n_jobs);
            task_pool.isDaemon = true;
            return task_pool;
        }

        auto task_pool = make_task_pool();
        // Task[] task_pool_tasks;
        shared bool[Recipe] visited_recipes;

        log.trace("executing solved recipes with %s jobs", options.n_jobs);

        auto current_in_degree = -1;

        foreach (i, ref node; toposorted_queue) {
            if (node.recipe in visited_recipes) {
                continue;
            }
            visited_recipes[node.recipe] = true;

            auto node_in_degree = node.in_degree;
            if (current_in_degree < 0)
                current_in_degree = node_in_degree;
            if (node_in_degree < current_in_degree) {
                // this node has a lower in-degree
                // meaning we have to wait for the previous nodes to finish
                synchronized {
                    log.trace(" current in-degree %s, next in-degree %s, waiting for previous nodes to finish",
                        current_in_degree, node_in_degree);
                }
                if (!use_single_thread) {
                    // wait for everything to finish
                    task_pool.finish(true);
                    // create new task pool
                    task_pool = make_task_pool();
                }
                current_in_degree = node_in_degree;
            }

            if (use_single_thread) {
                auto result = execute_node_recipe(task_pool, node, log);
                if (!result) {
                    return false;
                }
            } else {
                // queue on the task pool
                auto execute_task = task(&execute_node_recipe, task_pool, node, log);
                task_pool.put(execute_task);
            }
        }

        // task_pool.finish(true);

        return true;
    }

    bool execute_node_recipe(TaskPool pool, SolverNode node, Logger log) {
        auto recipe = node.recipe;
        // logger needs to be passed when multithreading

        auto worker_ix = pool.workerIndex;
        synchronized {
            log.trace(" [%s] maybe build %s with recipe '%s' <- %s",
                worker_ix,
                node.recipe.outputs, node.recipe.name, node.recipe.inputs
            );
        }

        bool cache_dirty = false;
        // if cache is enabled, look in the recipe cache
        if (options.enable_cache && recipe.name !is null) {
            // hash the current recipe
            auto current_recipe_cache = cast(long) recipe.hashOf();
            // get an existing recipe cache
            auto maybe_recipe_cache = db.get_recipe_cache(recipe.name);
            cache_dirty = maybe_recipe_cache.match!(
                (RecipeCache cache_item) => cache_item.hash != current_recipe_cache,
                () => false, // no existing cache item

                

            );
            if (maybe_recipe_cache.empty) {
                log.dbg(" [%s] no existing recipe cache for '%s'", worker_ix, recipe.name);
            }
            // store the current recipe cache
            db.update_recipe_cache(recipe.name, current_recipe_cache);
            log.trace("  [%s] recipe cache status for '%s': %s",
                worker_ix, recipe.name, cache_dirty ? "dirty" : "clean");
        }

        auto file_inputs = node.recipe.inputs
            .filter!(x => x.reality == Footprint.Reality.File).array;
        auto file_outputs = node.recipe.outputs
            .filter!(x => x.reality == Footprint.Reality.File).array;

        // 1. ensure all file inputs exist
        foreach (input; file_inputs) {
            if (!std.file.exists(input.name)) {
                synchronized {
                    log.err("  [%s] file input '%s' does not exist", worker_ix, input.name);
                }
                return false;
            }
        }
        // check if all outputs exist
        bool all_outputs_exist = file_outputs.length > 0 && file_outputs.all!(
            x => std.file.exists(x.name));

        if (cache_dirty) {
            log.trace("  [%s] recipe cache is dirty, forcing rebuild", worker_ix);
        } else {
            // recipe cache is clean

            if (all_outputs_exist) {
                // check if modtimes allow us to skip this recipe

                // get modtimes of all file inputs
                auto file_input_modtimes = file_inputs
                    .map!(x => std.file.timeLastModified(x.name).toUnixTime);
                // get modtimes of all file outputs
                auto file_output_modtimes = file_outputs
                    .map!(x => std.file.timeLastModified(x.name).toUnixTime);

                // if all file outputs are newer than all file inputs, we don't need to build
                auto newest_file_input_modtime = file_input_modtimes.maxElement;
                auto oldest_file_output_modtime = file_output_modtimes.minElement;
                if (newest_file_input_modtime < oldest_file_output_modtime) {
                    synchronized {
                        log.trace("  [%s] skipping %s because all outputs are newer than all inputs",
                            worker_ix, node.recipe.name);
                    }
                    return true;
                }
            }
        }

        foreach (step; recipe.steps) {
            // log.trace("  executing step %s", step);
            synchronized {
                log.trace("  [%s] executing step %s", worker_ix, step);
            }
            auto step_result = execute_step(log, step);
            if (!step_result) {
                synchronized {
                    log.err("  [%s] error executing step %s", worker_ix, step);
                }
                return false;
            }
        }

        // all steps finished, check that all outputs exist
        foreach (output; file_outputs) {
            if (!std.file.exists(output.name)) {
                synchronized {
                    log.err("  [%s] output '%s' does not exist after executing recipe '%s'",
                        worker_ix, output.name, recipe.name);
                }
                return false;
            }
        }

        return true;
    }

    bool execute_step(Logger log, CommandStep step) {
        import std.process;

        try {
            if (!step.is_quiet) {
                log.source = "cmd";
                synchronized {
                    log.info("%s", step.cmd);
                }
            }
            auto command_result = executeShell(step.cmd);
            if (command_result.status != 0) {
                log.err("error executing shell command: `%s`:\n%s", step.cmd, command_result.output);
                return false;
            }
            return true;
        } catch (Exception e) {
            log.err("exception executing shell command: `%s`: %s", step.cmd, e);
            return false;
        }
    }

    SolverNode[] toposort_solver_graph(SolverGraph solver_graph) {
        // topologically sort the graph iteratively using Kahn's algorithm
        int[SolverNode] in_degree;

        bool[SolverNode] visited;
        auto queue = DList!(SolverNode)();
        foreach (node; solver_graph.roots) {
            in_degree[node] = 0;
            queue.insertBack(node);
        }

        while (!queue.empty) {
            auto node = queue.front;
            queue.removeFront;

            if (node in visited) {
                continue;
            }

            visited[node] = true;
            node.in_degree = in_degree[node];

            foreach (child; node.children) {
                // update in-degree of the child
                if (child !in in_degree) {
                    in_degree[child] = 0;
                }
                in_degree[child] += 1;
                child.in_degree = in_degree[child];
                if (child in visited) {
                    continue;
                }
                queue.insertBack(child);
            }
        }

        SolverNode[] sorted_nodes;
        visited.clear();
        queue.clear();
        // queue the roots (they have in-degree 0)
        foreach (node; solver_graph.roots) {
            queue.insertBack(node);
        }

        while (!queue.empty) {
            auto node = queue.front;
            queue.removeFront;

            if (node in visited) {
                continue;
            }

            visited[node] = true;
            sorted_nodes ~= node;

            foreach (child; node.children) {
                // update in-degree of the child
                in_degree[child] -= 1;

                // if in-degree becomes 0, add it to queue
                if (in_degree[child] == 0) {
                    queue.insertBack(child);
                }
            }
        }
        enforce(sorted_nodes.length == visited.length, "graph has a cycle");

        // // print topologically sorted order
        // log.trace("topologically sorted order:");
        // foreach (node; sorted_nodes) {
        //     log.trace(" %s", node);
        // }

        return sorted_nodes;
    }

    SolverGraph build_solver_graph(Recipe[] goal_recipes, Recipe[] all_recipes) {
        // create a solver graph
        log.trace("creating solver graph");
        auto graph = new SolverGraph();

        Nullable!Recipe find_recipe_to_build(Footprint footprint) {
            // find a recipe that says it can build this footprint
            log.trace(" finding recipe to build footprint %s", footprint);
            foreach (recipe; all_recipes) {
                // log.trace("  checking if recipe '%s' can build footprint %s", recipe.name, footprint);
                if (recipe.can_build_footprint(footprint)) {
                    log.trace("   recipe '%s' can build footprint %s", recipe.name, footprint);
                    return Nullable!Recipe(recipe);
                }
            }
            return Nullable!Recipe.init;
        }

        Footprint[] get_dependencies(Recipe recipe) {
            // get the immediate dependencies of this recipe
            return recipe.inputs;
        }

        struct RecipeWalk {
            Recipe recipe;
            Nullable!Recipe parent_recipe;
            SolverNode[] parent_nodes;

            string toString() const {
                return format("RecipeWalk(recipe: '%s', parent: '%s', parent_nodes: %s)",
                    recipe.name,
                    parent_recipe.isNull ? "<null>" : parent_recipe.get.name,
                    parent_nodes
                );
            }
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
            // log.trace("processing recipe '%s'", walk.recipe.name);
            log.trace("processing recipe '%s' (parent: '%s')",
                walk.recipe.name,
                walk.parent_recipe.isNull ? "<null>" : walk.parent_recipe.get.name
            );

            // add graph nodes for the outputs
            SolverNode[] curr_nodes;
            foreach (output; walk.recipe.outputs) {
                // find or create node for this output footprint
                SolverNode output_node = null;
                if (output in nodes_for_footprints) {
                    // use existing node
                    output_node = nodes_for_footprints[output];
                    log.trace("  using node for output %s", output);
                } else {
                    // create a new node for this output
                    output_node = new SolverNode(output);
                    output_node.recipe = walk.recipe;
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
                    log.trace("   added root %s", output_node);
                }

                curr_nodes ~= output_node;
            }

            // add dependencies to the queue (from our inputs)
            foreach (dep; get_dependencies(walk.recipe)) {
                // find a recipe that can build this dependency
                auto maybe_dep_recipe = find_recipe_to_build(dep);
                if (maybe_dep_recipe.isNull) {
                    // couldn't find a recipe that can build this dependency
                    // see if it's a real file that exists
                    if (dep.reality == Footprint.Reality.File && std.file.exists(dep.name)) {
                        log.trace("  using real file %s", dep);
                        // this is a real file, which is a terminal
                        continue;
                    }
                    // otherwise, we don't know how to build this dependency
                    enforce(false, format("no recipe found that can build footprint %s", dep));
                    assert(0);
                }
                auto dep_walk = RecipeWalk(maybe_dep_recipe.get, Nullable!Recipe(walk.recipe), curr_nodes);

                if (dep_walk in visited_walks) {
                    // we've already visited this walk, so we don't need to add it to the queue
                    log.dbg("  already visited dependency walk %s", dep_walk);

                    continue;
                }

                // add it to the queue
                log.dbg("  adding dependency walk %s", dep_walk);
                recipe_queue.insertBack(dep_walk);
            }
        }

        // now it should be a real graph
        if (options.graphviz_file !is null) {
            dump_solver_graph(graph, options.graphviz_file);
        }

        return graph;
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
            // log.dbg(" gv node %s", node);
            auto reality = node.footprint.reality;
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
                // this is a child, add an edge then queue it
                // log.dbg("  gv edge %s -> %s", node, child);
                // gv.edge(node, child, ["style": "solid"]);
                gv_builder ~= format("  \"%s\" -> \"%s\" [style=solid];\n", node, child);

                // if child is not visited, add it to the queue
                if (child !in visited_nodes) {
                    node_stack.insertBack(child);
                }
            }
        }

        gv_builder ~= "}\n";

        // gv.save(filename);
        std.file.write(filename, gv_builder.data);
    }
}
