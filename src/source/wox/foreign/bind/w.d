module wox.foreign.bind.w;

import wox.log;
import wox.foreign.imports;
import wox.foreign.binder;
import wox.foreign.common;

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
            case "env(_,_)":
                return &W.env;
            case "glob(_)":
                return &W.glob;
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
            case "abspath(_)":
                return &W.abspath;
            case "file_exists(_)":
                return &W.file_exists;
            case "log_err(_)":
                return &W.log_err;
            case "log_wrn(_)":
                return &W.log_wrn;
            case "log_inf(_)":
                return &W.log_inf;
            case "log_trc(_)":
                return &W.log_trc;
            case "log_dbg(_)":
                return &W.log_dbg;
            case "shell(_)":
                return &W.shell;
            case "join(_,_)":
                return &W.join;
            default:
                enforce(0, format("failed to bind unknown method %s.%s", className, signature));
                assert(0);
            }
        }

        return null;
    }

    extern (C) struct W {
        // cliopts() -> list[string]
        static void cliopts(WrenVM* vm) {
            WrenUtils.wren_write_string_list(vm, 0, wox_context.args, 1);
        }

        // cliopt(name, default) -> string
        static void cliopt(WrenVM* vm) {
            auto name = WrenUtils.wren_expect_slot_string(vm, 1);
            auto def = WrenUtils.wren_expect_slot_nullable_string(vm, 2);

            auto string_opt = wox_context.parsed_args.opt(name.to!string);
            if (string_opt !is null)
                wrenSetSlotString(vm, 0, string_opt.toStringz);
            else if (def !is null)
                wrenSetSlotString(vm, 0, def.toStringz);
            else
                wrenSetSlotNull(vm, 0);
        }

        // cliopt_int(name, default) -> int
        static void cliopt_int(WrenVM* vm) {
            auto name = WrenUtils.wren_expect_slot_string(vm, 1);
            auto def = WrenUtils.wren_expect_slot_double(vm, 2);

            auto int_opt = wox_context.parsed_args.opt(name.to!string);
            if (int_opt is null) {
                wrenSetSlotDouble(vm, 0, def);
                return;
            }

            wrenSetSlotDouble(vm, 0, int_opt.to!double);
        }

        // cliopt_bool(name, default) -> bool
        static void cliopt_bool(WrenVM* vm) {
            auto name = WrenUtils.wren_expect_slot_string(vm, 1);
            auto def = wrenGetSlotBool(vm, 2);

            auto bool_opt = wox_context.parsed_args.flag(name.to!string);
            wrenSetSlotBool(vm, 0, bool_opt);
        }

        // env(name, default) -> string
        static void env(WrenVM* vm) {
            auto name = WrenUtils.wren_expect_slot_string(vm, 1).to!string;
            auto def = WrenUtils.wren_expect_slot_nullable_string(vm, 2);

            if (name in wox_context.env)
                wrenSetSlotString(vm, 0, wox_context.env[name].toStringz);
            else if (def !is null)
                wrenSetSlotString(vm, 0, def.toStringz);
            else
                wrenSetSlotNull(vm, 0);
        }

        // glob(pattern) -> list[string]
        static void glob(WrenVM* vm) {
            auto pattern = WrenUtils.wren_expect_slot_string(vm, 1);

            auto pattern_str = pattern.to!string;
            // convert glob expression to regex
            auto regex_like_pattern = pattern_str
                .replace(".", r"\.")
                .replace("?", ".")
                .replace("*", ".*");
            auto regex_str = format("^%s$", regex_like_pattern);
            auto matching_files = ForeignCommon.recursive_listdir_matching(".", regex_str);

            WrenUtils.wren_write_string_list(vm, 0, matching_files, 1);
        }

        // path_join(paths: list) -> string
        static void path_join(WrenVM* vm) {
            auto paths = WrenUtils.wren_read_string_list(vm, 1, 0);

            auto joined_path = std.path.buildPath(paths);

            wrenSetSlotString(vm, 0, joined_path.toStringz);
        }

        // path_split(path) -> list[string]
        static void path_split(WrenVM* vm) {
            auto path = WrenUtils.wren_expect_slot_string(vm, 1).to!string;

            auto path_segments = path.split(std.path.dirSeparator);

            WrenUtils.wren_write_string_list(vm, 0, path_segments, 1);
        }

        // path_dirname(path) -> string
        static void path_dirname(WrenVM* vm) {
            auto path = WrenUtils.wren_expect_slot_string(vm, 1).to!string;

            auto result = std.path.dirName(path);

            wrenSetSlotString(vm, 0, result.toStringz);
        }

        // path_basename(path) -> string
        static void path_basename(WrenVM* vm) {
            auto path = WrenUtils.wren_expect_slot_string(vm, 1).to!string;

            auto result = std.path.baseName(path);

            wrenSetSlotString(vm, 0, result.toStringz);
        }

        // path_extname(path) -> string
        static void path_extname(WrenVM* vm) {
            auto path = WrenUtils.wren_expect_slot_string(vm, 1).to!string;

            auto result = std.path.extension(path);

            wrenSetSlotString(vm, 0, result.toStringz);
        }

        // abspath(path) -> string
        static void abspath(WrenVM* vm) {
            auto path = WrenUtils.wren_expect_slot_string(vm, 1).to!string;

            auto result = std.path.absolutePath(path);

            wrenSetSlotString(vm, 0, result.toStringz);
        }

        // file_exists(path) -> bool
        static void file_exists(WrenVM* vm) {
            auto path = WrenUtils.wren_expect_slot_string(vm, 1).to!string;

            auto result = std.file.exists(path);
            wrenSetSlotBool(vm, 0, result);
        }

        // foreign static log_err(msg)                         // log err msg
        // foreign static log_wrn(msg)                         // log warn msg
        // foreign static log_inf(msg)                         // log info msg
        // foreign static log_trc(msg)                         // log trace msg

        // log_err(msg)
        static void log_err(WrenVM* vm) {
            auto msg = WrenUtils.wren_expect_slot_string(vm, 1).to!string;
            wox_context.buildscript_log.err(msg);
        }

        // log_wrn(msg)
        static void log_wrn(WrenVM* vm) {
            auto msg = WrenUtils.wren_expect_slot_string(vm, 1).to!string;
            wox_context.buildscript_log.wrn(msg);
        }

        // log_inf(msg)
        static void log_inf(WrenVM* vm) {
            auto msg = WrenUtils.wren_expect_slot_string(vm, 1).to!string;
            wox_context.buildscript_log.inf(msg);
        }

        // log_trc(msg)
        static void log_trc(WrenVM* vm) {
            auto msg = WrenUtils.wren_expect_slot_string(vm, 1).to!string;
            wox_context.buildscript_log.trc(msg);
        }

        // log_dbg(msg)
        static void log_dbg(WrenVM* vm) {
            auto msg = WrenUtils.wren_expect_slot_string(vm, 1).to!string;
            wox_context.buildscript_log.dbg(msg);
        }

        // shell(cmd) -> string
        static void shell(WrenVM* vm) {
            auto cmd = WrenUtils.wren_expect_slot_string(vm, 1).to!string;

            auto result = ForeignCommon.shell_execute(cmd);
            enforce(result !is null, "shell execute returned null");
            wrenSetSlotString(vm, 0, result.toStringz);
        }

        // join(list, sep) -> string
        static void join(WrenVM* vm) {
            auto list = WrenUtils.wren_read_string_list(vm, 1, 0);
            auto sep = WrenUtils.wren_expect_slot_string(vm, 2).to!string;

            auto result = list.join(sep);

            wrenSetSlotString(vm, 0, result.toStringz);
        }
    }
}
