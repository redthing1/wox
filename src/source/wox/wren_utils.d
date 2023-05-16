module wox.wren_utils;

import std.string;
import std.array;
import std.conv;

import wren;

static class WrenUtils {
    static string[] wren_read_string_list(WrenVM* vm, int list_slot, int temp_slot) {
        auto str_list_len = wrenGetListCount(vm, list_slot);
        string[] str_list_items;
        for (auto i = 0; i < str_list_len; i++) {
            wrenGetListElement(vm, list_slot, i, temp_slot);
            str_list_items ~= wrenGetSlotString(vm, temp_slot).to!string;
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

    static WrenHandle*[] wren_read_handle_list(WrenVM* vm, int list_slot, int temp_slot) {
        auto handle_list_len = wrenGetListCount(vm, list_slot);
        WrenHandle*[] list_item_handles;
        for (auto i = 0; i < handle_list_len; i++) {
            wrenGetListElement(vm, list_slot, i, temp_slot);
            // get a handle to the item
            auto item_handle = wrenGetSlotHandle(vm, temp_slot);
            list_item_handles ~= item_handle;
        }

        return list_item_handles;
    }

    static void wren_release_handles(WrenVM* vm, WrenHandle*[] handles) {
        foreach (handle; handles) {
            wrenReleaseHandle(vm, handle);
        }
    }
}
