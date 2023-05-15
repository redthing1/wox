module wox.foreign.wox_utils;

import wox.log;
import wox.foreign.imports;

struct ForeignWoxUtils {
    static WrenForeignMethodFn bind(
        WrenVM* vm, const(char)* module_, const(char)* className,
        bool isStatic, const(char)* signature
    ) @nogc nothrow {
        // printf("[ForeignWoxUtils::bind] %s::%s.%s\n", module_, className, signature);

        if (eq(className, "W")) {
            if (eq(signature, "cliargs()"))
                return &W.cliargs;
            else if (eq(signature, "cliarg(_,_)"))
                return &W.cliarg;
            else if (eq(signature, "cliarg_int(_,_)"))
                return &W.cliarg_int;
            else if (eq(signature, "cliarg_bool(_,_)"))
                return &W.cliarg_bool;
            else if (eq(signature, "glob(_)"))
                return &W.glob;
            else if (eq(signature, "ext_add(_,_)"))
                return &W.ext_add;
            else if (eq(signature, "ext_replace(_,_,_)"))
                return &W.ext_replace;
            else if (eq(signature, "ext_remove(_,_)"))
                return &W.ext_remove;
            else if (eq(signature, "path_join(_)"))
                return &W.path_join;
            else if (eq(signature, "path_split(_)"))
                return &W.path_split;
            else if (eq(signature, "path_dirname(_)"))
                return &W.path_dirname;
            else if (eq(signature, "path_basename(_)"))
                return &W.path_basename;
            else if (eq(signature, "path_extname(_)"))
                return &W.path_extname;
        }

        return null;
    }

    struct W {
        // cliargs() -> list[string]
        static void cliargs(WrenVM* vm) @nogc nothrow {
            // stub: return empty list
            wrenSetSlotNewList(vm, 0);
        }

        // cliarg(name, default) -> string
        static void cliarg(WrenVM* vm) @nogc nothrow {
            auto name = wrenGetSlotString(vm, 1);
            auto def = wrenGetSlotString(vm, 2);

            // stub: return default
            wrenSetSlotString(vm, 0, def);
        }

        // cliarg_int(name, default) -> int
        static void cliarg_int(WrenVM* vm) @nogc nothrow {
            auto name = wrenGetSlotString(vm, 1);
            auto def = wrenGetSlotDouble(vm, 2);

            // stub: return default
            wrenSetSlotDouble(vm, 0, def);
        }

        // cliarg_bool(name, default) -> bool
        static void cliarg_bool(WrenVM* vm) @nogc nothrow {
            auto name = wrenGetSlotString(vm, 1);
            auto def = wrenGetSlotBool(vm, 2);

            // stub: return default
            wrenSetSlotBool(vm, 0, def);
        }

        // glob(pattern) -> list[string]
        static void glob(WrenVM* vm) @nogc nothrow {
            auto pattern = wrenGetSlotString(vm, 1);

            // stub: return empty list
            wrenSetSlotNewList(vm, 0);
        }

        // ext_add(paths: list, ext) -> list[string]
        static void ext_add(WrenVM* vm) @nogc nothrow {
            auto paths_len = wrenGetListCount(vm, 1);
            auto ext = wrenGetSlotString(vm, 2);

            // stub: return empty list
            wrenSetSlotNewList(vm, 0);
        }

        // ext_replace(paths: list, ext, new_ext) -> list[string]
        static void ext_replace(WrenVM* vm) @nogc nothrow {
            auto paths_len = wrenGetListCount(vm, 1);
            auto ext = wrenGetSlotString(vm, 2);
            auto new_ext = wrenGetSlotString(vm, 3);

            // stub: return empty list
            wrenSetSlotNewList(vm, 0);
        }

        // ext_remove(paths: list, ext) -> list[string]
        static void ext_remove(WrenVM* vm) @nogc nothrow {
            auto paths_len = wrenGetListCount(vm, 1);
            auto ext = wrenGetSlotString(vm, 2);

            // stub: return empty list
            wrenSetSlotNewList(vm, 0);
        }

        // path_join(paths: list) -> string
        static void path_join(WrenVM* vm) @nogc nothrow {
            auto paths_len = wrenGetListCount(vm, 1);

            // stub: return empty string
            wrenSetSlotString(vm, 0, "");
        }

        // path_split(path) -> list[string]
        static void path_split(WrenVM* vm) @nogc nothrow {
            auto path = wrenGetSlotString(vm, 1);

            // stub: return empty list
            wrenSetSlotNewList(vm, 0);
        }

        // path_dirname(path) -> string
        static void path_dirname(WrenVM* vm) @nogc nothrow {
            auto path = wrenGetSlotString(vm, 1);

            // stub: return empty string
            wrenSetSlotString(vm, 0, "");
        }

        // path_basename(path) -> string
        static void path_basename(WrenVM* vm) @nogc nothrow {
            auto path = wrenGetSlotString(vm, 1);

            // stub: return empty string
            wrenSetSlotString(vm, 0, "");
        }

        // path_extname(path) -> string
        static void path_extname(WrenVM* vm) @nogc nothrow {
            auto path = wrenGetSlotString(vm, 1);

            // stub: return empty string
            wrenSetSlotString(vm, 0, "");
        }
    }
}
