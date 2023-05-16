module wox.foreign.utils;

import std.regex;

import wox.foreign.imports;
import wox.foreign.utils;

static struct Utils {
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

    static string[] wren_read_string_list(WrenVM* vm, int list_slot, int temp_slot) {
        auto str_list_len = wrenGetListCount(vm, 1);
        string[] str_list_items;
        for (auto i = 0; i < str_list_len; i++) {
            wrenGetListElement(vm, 1, i, temp_slot);
            str_list_items ~= wrenGetSlotString(vm, 0).to!string;
        }

        return str_list_items;
    }

    static void wren_write_string_list(WrenVM* vm, int list_slot, string[] str_list_items, int temp_slot) {
        wrenEnsureSlots(vm, temp_slot + 1);
        // create a new list in the destination slot
        wrenSetSlotNewList(vm, list_slot);

        for (auto i = 0; i < str_list_items.length; i++) {
            // put the item in a slot
            wrenSetSlotString(vm, temp_slot, str_list_items[i].toStringz);
            // add the item to the list
            wrenInsertInList(vm, list_slot, i, temp_slot);
        }
    }
}
