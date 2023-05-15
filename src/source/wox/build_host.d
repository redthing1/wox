module wox.build_host;

import std.stdio;
import std.file;
import std.path;
import std.string;
import wren.compiler;
import wren.vm;

import wox.log;

class BuildHost {
    Logger log;

    this(Logger log) {
        this.log = log;
    }

    static void wren_write(WrenVM* vm, const(char)* text) @nogc nothrow {
        printf("%s", text);
    }

    static void wren_error(
        WrenVM* vm, WrenErrorType errorType, const(char)* module_, int line, const(char)* msg
    ) @nogc nothrow {
        switch (errorType) with (WrenErrorType) {
        case WREN_ERROR_COMPILE: {
                printf("[%s line %d] [Error] %s\n", module_, line, msg);
                break;
            }
        case WREN_ERROR_STACK_TRACE: {
                printf("[%s line %d] in %s\n", module_, line, msg);
                break;
            }
        case WREN_ERROR_RUNTIME: {
                printf("[Runtime Error] %s\n", msg);
                break;
            }
        default: {
                printf("Unknown Error\n");
                break;
            }
        }
    }

    bool build(string buildfile_contents, string[] targets, string[] args) {
        WrenConfiguration config;
        wrenInitConfiguration(&config);
        config.writeFn = &wren_write;
        config.errorFn = &wren_error;

        WrenVM* vm = wrenNewVM(&config);

        return false;
    }
}
