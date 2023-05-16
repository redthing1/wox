module wox.build_host;

import std.stdio;
import std.file;
import std.path;
import std.conv;
import std.string;
import wren;
import core.stdc.stdio;
import core.stdc.string;

import wox.log;
import wox.foreign.binder;
import wox.wren_utils;

enum WOX_SCRIPT = import("wox.wren");

enum WOX_MODULE = "wox";
enum BUILDSCRIPT_MODULE = "build";

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

    bool build(string buildscript, string[] targets, string cwd, string[] args, string[string] env) {
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
        // get handle to the default recipe
        auto default_recipe_h = wrenGetSlotHandle(vm, 0);
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

        return true;
    }
}
