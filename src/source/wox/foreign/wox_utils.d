module wox.foreign.wox_utils;

import wox.log;
import wox.foreign.imports;
import wox.foreign.binder;
import wox.foreign.utils;

struct ForeignWoxUtils {
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
            // put all the cli args into a new list
            wrenSetSlotNewList(vm, 0);
            wrenEnsureSlots(vm, cast(int)(1 + wox_context.args.length));

            foreach (i, arg; wox_context.args) {
                auto el_ix = cast(int)(i + 1);
                wrenSetSlotString(vm, el_ix, arg.toStringz);
                wrenInsertInList(vm, 0, cast(int) i, el_ix);
            }
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

            // put all the matching files into a new list
            wrenSetSlotNewList(vm, 0);
            wrenEnsureSlots(vm, cast(int)(1 + matching_files.length));

            foreach (i, file; matching_files) {
                auto el_ix = cast(int)(i + 1);
                wrenSetSlotString(vm, el_ix, file.toStringz);
                wrenInsertInList(vm, 0, cast(int) i, el_ix);
            }
        }

        // ext_add(paths: list, ext) -> list[string]
        static void ext_add(WrenVM* vm) {
            auto paths_len = wrenGetListCount(vm, 1);
            auto ext = wrenGetSlotString(vm, 2).to!string;

            string[] results;
            for (auto i = 0; i < paths_len; i++) {
                // grab elements and put them in slot 0 temporarily
                wrenGetListElement(vm, 1, i, 0);
                auto path = wrenGetSlotString(vm, 0).to!string;
                results ~= path ~ ext;
            }

            // put all the results into a new list
            wrenSetSlotNewList(vm, 0);
            wrenEnsureSlots(vm, cast(int)(1 + results.length));

            foreach (i, result; results) {
                auto el_ix = cast(int)(i + 1);
                wrenSetSlotString(vm, el_ix, result.toStringz);
                wrenInsertInList(vm, 0, cast(int) i, el_ix);
            }
        }

        // ext_replace(paths: list, ext, new_ext) -> list[string]
        static void ext_replace(WrenVM* vm) {
            auto paths_len = wrenGetListCount(vm, 1);
            auto ext = wrenGetSlotString(vm, 2).to!string;
            auto new_ext = wrenGetSlotString(vm, 3).to!string;

            string[] results;
            for (auto i = 0; i < paths_len; i++) {
                // grab elements and put them in slot 0 temporarily
                wrenGetListElement(vm, 1, i, 0);
                auto path = wrenGetSlotString(vm, 0).to!string;
                results ~= path.replace(ext, new_ext);
            }

            // put all the results into a new list
            wrenSetSlotNewList(vm, 0);
            wrenEnsureSlots(vm, cast(int)(1 + results.length));

            foreach (i, result; results) {
                auto el_ix = cast(int)(i + 1);
                wrenSetSlotString(vm, el_ix, result.toStringz);
                wrenInsertInList(vm, 0, cast(int) i, el_ix);
            }
        }

        // ext_remove(paths: list, ext) -> list[string]
        static void ext_remove(WrenVM* vm) {
            auto paths_len = wrenGetListCount(vm, 1);
            auto ext = wrenGetSlotString(vm, 2).to!string;

            string[] results;
            for (auto i = 0; i < paths_len; i++) {
                // grab elements and put them in slot 0 temporarily
                wrenGetListElement(vm, 1, i, 0);
                auto path = wrenGetSlotString(vm, 0).to!string;
                if (ext == "") {
                    // if ext is empty, remove the last extension
                    auto last_dot_ix = path.lastIndexOf(".");
                    results ~= path[0 .. last_dot_ix];
                } else {
                    // otherwise, remove the specified extension
                    results ~= path.replace(ext, "");
                }
            }

            // put all the results into a new list
            wrenSetSlotNewList(vm, 0);
            wrenEnsureSlots(vm, cast(int)(1 + results.length));

            foreach (i, result; results) {
                auto el_ix = cast(int)(i + 1);
                wrenSetSlotString(vm, el_ix, result.toStringz);
                wrenInsertInList(vm, 0, cast(int) i, el_ix);
            }
        }

        // path_join(paths: list) -> string
        static void path_join(WrenVM* vm) {
            auto paths_len = wrenGetListCount(vm, 1);

            string[] path_segments;
            for (auto i = 0; i < paths_len; i++) {
                // grab elements and put them in slot 0 temporarily
                wrenGetListElement(vm, 1, i, 0);
                auto path = wrenGetSlotString(vm, 0).to!string;
                path_segments ~= path;
            }
            string joined_path = std.path.buildPath(path_segments);

            wrenSetSlotString(vm, 0, joined_path.toStringz);
        }

        // path_split(path) -> list[string]
        static void path_split(WrenVM* vm) {
            auto path = wrenGetSlotString(vm, 1).to!string;

            auto path_segments = path.split(std.path.dirSeparator);
            // put all the path segments into a new list
            wrenSetSlotNewList(vm, 0);
            wrenEnsureSlots(vm, cast(int)(1 + path_segments.length));
            foreach (i, path_segment; path_segments) {
                auto el_ix = cast(int)(i + 1);
                wrenSetSlotString(vm, el_ix, path_segment.toStringz);
                wrenInsertInList(vm, 0, cast(int) i, el_ix);
            }
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
