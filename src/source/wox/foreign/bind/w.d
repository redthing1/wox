module wox.foreign.bind.w;

import wox.log;
import wox.foreign.imports;
import wox.foreign.binder;
import wox.foreign.utils;

struct BindForeignW {
    static WrenForeignMethodFn bind(
        WrenVM* vm, string moduleName, string className, string signature, bool isStatic
    ) {
        if (className == "W") {
            switch (signature) {
            case "cliopts()":
                return &W.cliopts;
            case "cliopt(_,_)":
                return &W.cliopt;
            case "cliopt_int(_,_)":
                return &W.cliopt_int;
            case "cliopt_bool(_,_)":
                return &W.cliopt_bool;
            case "glob(_)":
                return &W.glob;
            case "ext_add(_,_)":
                return &W.ext_add;
            case "ext_replace(_,_,_)":
                return &W.ext_replace;
            case "ext_remove(_,_)":
                return &W.ext_remove;
            case "path_join(_)":
                return &W.path_join;
            case "path_split(_)":
                return &W.path_split;
            case "path_dirname(_)":
                return &W.path_dirname;
            case "path_basename(_)":
                return &W.path_basename;
            case "path_extname(_)":
                return &W.path_extname;
            default:
                enforce(0, format("failed to bind unknown method %s.%s", className, signature));
                assert(0);
            }
        }

        return null;
    }

    struct W {
        // cliopts() -> list[string]
        static void cliopts(WrenVM* vm) {
            Utils.wren_write_string_list(vm, 0, wox_context.args, 1);
        }

        // cliopt(name, default) -> string
        static void cliopt(WrenVM* vm) {
            auto name = wrenGetSlotString(vm, 1);
            auto def = wrenGetSlotString(vm, 2);

            auto string_opt = wox_context.parsed_args.opt(name.to!string);
            if (string_opt is null) {
                wrenSetSlotString(vm, 0, def);
                return;
            }

            wrenSetSlotString(vm, 0, string_opt.toStringz);
        }

        // cliopt_int(name, default) -> int
        static void cliopt_int(WrenVM* vm) {
            auto name = wrenGetSlotString(vm, 1);
            auto def = wrenGetSlotDouble(vm, 2);

            auto int_opt = wox_context.parsed_args.opt(name.to!string);
            if (int_opt is null) {
                wrenSetSlotDouble(vm, 0, def);
                return;
            }

            wrenSetSlotDouble(vm, 0, int_opt.to!double);
        }

        // cliopt_bool(name, default) -> bool
        static void cliopt_bool(WrenVM* vm) {
            auto name = wrenGetSlotString(vm, 1);
            auto def = wrenGetSlotBool(vm, 2);

            auto bool_opt = wox_context.parsed_args.flag(name.to!string);
            wrenSetSlotBool(vm, 0, bool_opt);
        }

        // glob(pattern) -> list[string]
        static void glob(WrenVM* vm) {
            auto pattern = wrenGetSlotString(vm, 1);

            auto pattern_str = pattern.to!string;
            // convert glob expression to regex
            auto regex_str = pattern_str.replace("*", ".*");
            auto matching_files = Utils.recursive_listdir_matching(".", regex_str);

            Utils.wren_write_string_list(vm, 0, matching_files, 1);
        }

        // ext_add(paths: list, ext) -> list[string]
        static void ext_add(WrenVM* vm) {
            auto paths = Utils.wren_read_string_list(vm, 1, 0);
            auto ext = wrenGetSlotString(vm, 2).to!string;

            foreach (i, path; paths) {
                // append extension to each path
                paths[i] = path ~ ext;
            }

            Utils.wren_write_string_list(vm, 0, paths, 1);
        }

        // ext_replace(paths: list, ext, new_ext) -> list[string]
        static void ext_replace(WrenVM* vm) {
            auto paths = Utils.wren_read_string_list(vm, 1, 0);
            auto ext = wrenGetSlotString(vm, 2).to!string;
            auto new_ext = wrenGetSlotString(vm, 3).to!string;

            foreach (i, path; paths) {
                // replace extension in each path
                paths[i] = path.replace(ext, new_ext);
            }

            Utils.wren_write_string_list(vm, 0, paths, 1);
        }

        // ext_remove(paths: list, ext) -> list[string]
        static void ext_remove(WrenVM* vm) {
            auto paths = Utils.wren_read_string_list(vm, 1, 0);
            auto ext = wrenGetSlotString(vm, 2).to!string;

            foreach (i, path; paths) {
                // remove extension from each path
                if (ext == "") {
                    // if ext is empty, remove the last extension
                    auto last_dot_ix = path.lastIndexOf(".");
                    paths[i] = path[0 .. last_dot_ix];
                } else {
                    // otherwise, remove the specified extension
                    paths[i] = path.replace(ext, "");
                }
            }

            Utils.wren_write_string_list(vm, 0, paths, 1);
        }

        // path_join(paths: list) -> string
        static void path_join(WrenVM* vm) {
            auto paths = Utils.wren_read_string_list(vm, 1, 0);

            auto joined_path = std.path.buildPath(paths);

            wrenSetSlotString(vm, 0, joined_path.toStringz);
        }

        // path_split(path) -> list[string]
        static void path_split(WrenVM* vm) {
            auto path = wrenGetSlotString(vm, 1).to!string;

            auto path_segments = path.split(std.path.dirSeparator);

            Utils.wren_write_string_list(vm, 0, path_segments, 1);
        }

        // path_dirname(path) -> string
        static void path_dirname(WrenVM* vm) {
            auto path = wrenGetSlotString(vm, 1).to!string;

            auto result = std.path.dirName(path);

            wrenSetSlotString(vm, 0, result.toStringz);
        }

        // path_basename(path) -> string
        static void path_basename(WrenVM* vm) {
            auto path = wrenGetSlotString(vm, 1).to!string;

            auto result = std.path.baseName(path);

            wrenSetSlotString(vm, 0, result.toStringz);
        }

        // path_extname(path) -> string
        static void path_extname(WrenVM* vm) {
            auto path = wrenGetSlotString(vm, 1).to!string;

            auto result = std.path.extension(path);

            wrenSetSlotString(vm, 0, result.toStringz);
        }
    }
}
