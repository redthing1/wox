module wox.host.builder;

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
import std.range : zip;
import core.atomic;
import wren;
import miniorm;
import optional;

import wox.log;
import wox.models;
import wox.host.meta;
import wox.foreign.binder;
import wox.db;
import wox.host.solver;
import wox.wren;

class WoxBuilder {
    static Logger log;

    struct Options {
        int n_jobs = 1;
        string graphviz_file = null;
        bool enable_cache = false;
        bool list_targets = false;
        bool dry_run = false;
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

        if (options.dry_run) {
            // dry run implies 1 job
            options.n_jobs = 1;
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
                log.err("[wren] compile error at %s:%d: %s", module_.to!string, line, msg
                        .to!string);
                break;
            }
        case WREN_ERROR_STACK_TRACE: {
                log.err("[wren] error at %s:%d: %s", module_.to!string, line, msg
                        .to!string);
                break;
            }
        case WREN_ERROR_RUNTIME: {
                log.err("[wren] runtime error: %s", msg.to!string);
                break;
            }
        default: {
                log.err("[wren] unknown error: %s", msg.to!string);
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

    bool build(
        string buildscript_module_name, string buildscript, string[] requested_targets,
        string cwd, string[] args, string[string] env
    ) {
        // log.trace("buildscript:\n%s", buildscript);

        // // vm info
        // auto wren_ver = wrenGetVersionNumber();
        // log.trace("wren version: %s", wren_ver);

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
        auto buildscript_run_result = wrenInterpret(vm, buildscript_module_name.toStringz, buildscript
                .toStringz);
        if (buildscript_run_result != WREN_RESULT_SUCCESS) {
            log.err("failed to run buildscript module");
            return false;
        }

        auto wren_ext = new WrenExt(vm);

        if (wren_ext.get_global_var_type(buildscript_module_name, "Build") != WREN_TYPE_UNKNOWN) {
            log.err("buildscript module does not export a Build class");
            return false;
        }
        auto build_class_h = wren_ext.get_global_var_handle(buildscript_module_name, "Build", WREN_TYPE_UNKNOWN);
        auto default_recipe_name = wren_ext.call_prop_string(build_class_h, "default_recipe");
        auto all_recipes_h = wren_ext.call_prop_handle_list(build_class_h, "recipes");

        auto models_converter = ModelsFromWrenConverter(log, vm);

        auto all_recipes = all_recipes_h
            .map!(x => models_converter.convert_recipe_from_wren(x)).array;
        // find the default recipe in the list
        auto maybe_default_recipe = all_recipes.filter!(x => x.name == default_recipe_name);
        if (maybe_default_recipe.empty) {
            log.err("specified default recipe %s not found", default_recipe_name);
            return false;
        }
        auto default_recipe = maybe_default_recipe.front;

        if (options.list_targets) {
            pretty_dump_targets(default_recipe, all_recipes);
            return true;
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
            log.dbg("resolved recipe:\n%s", recipe);
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
                log.dbg("  resolving %s", *fp);
                // unknown reality means we don't know if it's a file or virtual
                // so we check if it's a file using some heuristics

                if (std.file.exists(fp.name)) { // is it a real file?
                    fp.reality = Footprint.Reality.File;
                    log.dbg("   %s is a file", *fp);
                } else if (fp.name.startsWith(".")) { // is it a relative path?
                    fp.reality = Footprint.Reality.File;
                    log.dbg("   %s is probably a file", *fp);
                } else if (fp.name.canFind("/") || fp.name.canFind(".")) { // is it a path?
                    fp.reality = Footprint.Reality.File;
                    log.dbg("   %s is probably a file", *fp);
                } else {
                    fp.reality = Footprint.Reality.Virtual;
                    log.dbg("   assuming %s is virtual", *fp);
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
        // build a graph of the recipes
        auto solver = new WoxSolver(log, goal_recipes, all_recipes);
        auto solver_graph = solver.build_graph();

        if (options.graphviz_file !is null) {
            log.trace("dumping solver graph to %s", options.graphviz_file);
            auto graphviz_dump = solver.dump_as_graphviz(solver_graph);
            std.file.write(options.graphviz_file, graphviz_dump);
        }

        auto raw_toposorted_nodes = solver.toposort_graph(solver_graph);

        auto toposorted_queue = raw_toposorted_nodes.reverse;

        log.trace("toposorted queue:");
        foreach (node; toposorted_queue) {
            log.trace(" [%s] %s > '%s'",
                node.toposort_depth, node.footprint, node.recipe.name
            );
        }

        // now, we have a list of nodes
        // they are ordered with the top-level targets first, so we can work backwards

        auto use_single_thread = options.n_jobs == 1;
        // auto task_pool = new TaskPool(options.n_jobs);
        // task_pool.isDaemon = true;
        TaskPool make_task_pool() {
            auto task_pool = new TaskPool(options.n_jobs);
            // task_pool.isDaemon = true;
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

            auto node_in_degree = node.toposort_depth;
            if (current_in_degree < 0)
                current_in_degree = node_in_degree;
            if (node_in_degree < current_in_degree) {
                // this node has a lower in-degree
                // meaning we have to wait for the previous nodes to finish
                synchronized {
                    log.dbg(" current in-degree %s, next in-degree %s, waiting for previous nodes to finish",
                        current_in_degree, node_in_degree);
                }
                if (!use_single_thread) {
                    // wait for everything to finish
                    task_pool.finish(true);
                    // create new task pool
                    task_pool = make_task_pool();
                }
                synchronized {
                    current_in_degree = node_in_degree;
                    log.dbg(" all previous nodes finished, in-degree now %s", current_in_degree);
                }
            }

            if (options.dry_run) {
                import colorize : cwritefln, color, fg;

                enforce(log.use_colors, "dry run requires color output");
                auto sb = appender!string;

                sb ~= "[dry run]".color(fg.light_black)
                    ~ " recipe '"
                    ~ format("%s", node.recipe.name).color(fg.green)
                    ~ "'\n";
                auto emph_col = fg.blue;
                auto emph2_col = fg.red;
                sb ~= "  inputs  : "
                    ~ format("%s", node.recipe.inputs).color(emph_col)
                    ~ "\n";
                sb ~= "  outputs : "
                    ~ format("%s", node.recipe.outputs).color(emph_col)
                    ~ "\n";
                if (!node.recipe.steps.empty) {
                    sb ~= "  steps:\n";
                    foreach (step; node.recipe.steps) {
                        sb ~= "    "
                            ~ format("%s", step).color(emph2_col)
                            ~ "\n";
                    }
                }

                cwritefln(sb.data.stripRight);
                continue;
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

        // log.warn("calling finish on task pool");
        task_pool.finish(true);

        return true;
    }

    bool execute_node_recipe(TaskPool pool, WoxSolver.Node node, Logger log) {
        try {
            auto recipe = node.recipe;
            // logger needs to be passed when multithreading

            auto worker_ix = pool.workerIndex;
            synchronized {
                log.trace(" [%s] maybe build %s with recipe '%s' <- %s",
                    worker_ix,
                    node.recipe.outputs, node.recipe.name, node.recipe.inputs
                );
            }

            // // die
            // enforce(0, "boz");

            bool cache_dirty = false;
            // if cache is enabled, look in the recipe cache
            synchronized {
                if (options.enable_cache && recipe.name !is null) {
                    // hash the current recipe
                    auto current_recipe_cache = cast(long) recipe.hashOf();
                    // get an existing recipe cache
                    auto maybe_recipe_cache = db.get_recipe_cache(recipe.name);
                    cache_dirty = maybe_recipe_cache.match!(
                        (RecipeCache cache_item) => cache_item.hash != current_recipe_cache,
                        () => false,
                    );
                    if (maybe_recipe_cache.empty) {
                        log.dbg(" [%s] no existing recipe cache for '%s'", worker_ix, recipe.name);
                    }
                    // store the current recipe cache
                    db.update_recipe_cache(recipe.name, current_recipe_cache);
                    log.trace("  [%s] recipe cache status for '%s': %s",
                        worker_ix, recipe.name, cache_dirty ? "dirty" : "clean");
                }
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

                    auto file_input_modtimes = file_inputs
                        .map!(x => std.file.timeLastModified(x.name).toUnixTime);
                    auto file_output_modtimes = file_outputs
                        .map!(x => std.file.timeLastModified(x.name).toUnixTime);

                    // auto file_input_modtime_pairs = zip(file_inputs, file_input_modtimes);
                    // auto file_output_modtime_pairs = zip(file_outputs, file_output_modtimes);

                    // // just dump everything
                    // foreach (pair; file_input_modtime_pairs) {
                    //     log.dbg("  [%s] input '%s' modtime %s",
                    //         worker_ix, pair[0].name, pair[1]);
                    // }
                    // foreach (pair; file_output_modtime_pairs) {
                    //     log.dbg("  [%s] output '%s' modtime %s",
                    //         worker_ix, pair[0].name, pair[1]);
                    // }

                    // if all file outputs are newer than all file inputs, we don't need to build
                    auto newest_file_input_modtime = file_input_modtimes.maxElement;
                    auto oldest_file_output_modtime = file_output_modtimes.minElement;

                    if (newest_file_input_modtime <= oldest_file_output_modtime) {
                        synchronized {
                            log.dbg("  [%s] skipping '%s' because all outputs are newer than all inputs",
                                worker_ix, node.recipe.name);
                        }
                        return true;
                    } else {
                        synchronized {
                            log.dbg("  [%s] not all outputs of '%s' are newer than all inputs, build required",
                                worker_ix, node.recipe.name);
                        }
                    }
                } else {
                    if (!file_outputs.empty) {
                        synchronized {
                            log.dbg("  [%s] not all outputs of '%s' exist, build required",
                                worker_ix, node.recipe.name);
                        }
                    }
                }
            }

            foreach (step; recipe.steps) {
                // if (options.dry_run) {
                //     log.warn("  [%s] would execute %s", worker_ix, step);
                //     continue;
                // }
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
                // if (options.dry_run) break; // don't check output existence in dry run
                if (!std.file.exists(output.name)) {
                    synchronized {
                        log.err("  [%s] output '%s' does not exist after executing recipe '%s'",
                            worker_ix, output.name, recipe.name);
                    }
                    return false;
                }
            }

            return true;
        } catch (Exception e) {
            synchronized {
                log.err("  [%s] exception executing recipe '%s': %s",
                    pool.workerIndex, node.recipe.name, e);
            }
            return false;
        }
    }

    bool execute_step(Logger log, StepInfo step) {
        import colorize : color, fg;

        switch (step.type) {
        case StepInfo.Type.Command: {
                import std.process;

                try {
                    if (!step.is_quiet) {
                        log.source = "cmd";
                        synchronized {
                            log.info("%s", step.data.color(fg.green));
                        }
                    }
                    // auto command_result = executeShell(step.data);
                    auto shellPid = spawnShell(step.data);
                    auto command_result = shellPid.wait();
                    // if (command_result.status != 0) {
                    if (command_result != 0) {
                        // log.err("error executing shell command: `%s`:\n%s", step.data, command_result
                        //         .output);
                        log.err("error executing shell command: `%s`", step);
                        return false;
                    }
                    return true;
                } catch (Exception e) {
                    log.err("exception executing shell command: `%s`: %s", step, e);
                    return false;
                }
            }
        case StepInfo.Type.Log: {
                log.source = "log";
                synchronized {
                    log.info("%s", step.data);
                }
                return true;
            }
        default:
            assert(0, "unknown step type");
        }

    }

    void pretty_dump_targets(Recipe default_recipe, Recipe[] all_recipes) {
        import colorize : cwritefln, color, fg;

        auto sb = appender!string;

        sb ~= "available targets:\n";
        auto col_name = fg.green;
        auto col_em = fg.blue;
        foreach (recipe; all_recipes) {
            sb ~= "  "
                ~ format("%s", recipe.name).color(col_name)
                ~ "\n";
            sb ~= "    dep: "
                ~ format("%s", recipe.inputs).color(col_em)
                ~ "\n";
            sb ~= "    out: "
                ~ format("%s", recipe.outputs).color(col_em)
                ~ "\n";
        }

        sb ~= "\n";
        sb ~= "default target: "
            ~ format("%s", default_recipe.name).color(col_name)
            ~ "\n";

        cwritefln(sb.data.stripRight);
    }
}
