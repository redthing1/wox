module wox.build_host;

import std.stdio;
import std.file;
import std.path;
import std.string;
import wren.compiler;
import wren.vm;
import wren.common;
import core.stdc.stdio;
import core.stdc.string;

import wox.log;
import wox.foreign.binder;

enum WOX_SCRIPT = import("wox.wren");

enum WOX_MODULE = "wox";
enum BUILDSCRIPT_MODULE = "build";

class BuildHost {
    Logger log;

    this(Logger log) {
        this.log = log;
    }

    static void wren_write(WrenVM* vm, const(char)* text) {
        printf("%s", text);
    }

    static void wren_error(
        WrenVM* vm, WrenErrorType errorType, const(char)* module_, int line, const(char)* msg
    ) {
        switch (errorType) with (WrenErrorType) {
        case WREN_ERROR_COMPILE: {
                printf("[wren] Error in %s at line %d: %s\n", module_, line, msg);
                break;
            }
        case WREN_ERROR_STACK_TRACE: {
                printf("[wren] Error in %s at line %d: %s\n", module_, line, msg);
                break;
            }
        case WREN_ERROR_RUNTIME: {
                printf("[wren] Runtime Error: %s\n", msg);
                break;
            }
        default: {
                printf("[wren] Unknown Error: %s\n", msg);
                break;
            }
        }
    }

    bool build(string buildscript, string[] targets, string[] args, string[string] env) {
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
        WoxBuildForeignBinder.initialize(WoxForeignContext(args, env));
        config.bindForeignMethodFn = &WoxBuildForeignBinder.bindForeignMethod;

        // create vm
        WrenVM* vm = wrenNewVM(&config);

        // create the wox module
        log.trace("loading wox module");
        auto woxModule = wrenInterpret(vm, WOX_MODULE.toStringz, WOX_SCRIPT.toStringz);

        // run buildscript module
        auto result = wrenInterpret(vm, BUILDSCRIPT_MODULE.toStringz, buildscript.toStringz);

        return false;
    }
}
