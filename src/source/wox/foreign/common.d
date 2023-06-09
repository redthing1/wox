module wox.foreign.common;

import std.regex;

import wox.foreign.imports;
import wox.foreign.binder;

static struct ForeignCommon {
    static string[] listdir(string path, bool recursive) {
        import std.algorithm.iteration : map, filter;
        import std.array : array;
        import std.path : baseName;

        auto span_mode = recursive ? SpanMode.depth : SpanMode.shallow;

        return dirEntries(path, span_mode)
            .filter!(a => a.isFile)
            .map!((return a) => (a.name))
            .array;
    }

    static string[] recursive_listdir_matching(string path, string pattern) {
        auto pattern_regex = regex(pattern);

        auto all_files = listdir(path, true);
        string[] matched_files;
        foreach (file_path; all_files) {
            auto match = file_path.matchFirst(pattern_regex);
            if (!match.empty) {
                matched_files ~= file_path;
            }
        }

        // writefln("all files: %s", all_files);
        // writefln("pattern: %s", pattern);
        // writefln("matched files: %s", matched_files);

        return matched_files;
    }

    static string shell_execute(string command) {
        import std.process;

        wox_context.wox_log.trace("executing shell command: `%s`", command);

        try {
            auto command_result = executeShell(command);
            auto command_output = command_result.output.strip();
            if (command_output is null) command_output = "";
            else command_output = command_output.idup;
            wox_context.wox_log.dbg("  command output: `%s`", command_output);
            return command_output;
        } catch (Exception e) {
            wox_context.wox_log.err("error executing shell command: `%s`: %s", command, e);
            return null;
        }
    }
}
