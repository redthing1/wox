module wox.wren.wren_utils;

import std.string;
import std.array;
import std.conv;
import std.exception : enforce;

import wren;

static class WrenUtils {
    static string[] wren_read_string_list(WrenVM* vm, int list_slot, int temp_slot) {
        // ensure the item in the slot is a list
        enforce(wrenGetSlotType(vm, list_slot) == WREN_TYPE_LIST,
            format("expected a list in slot %d", list_slot));
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
        // ensure the item in the slot is a list
        enforce(wrenGetSlotType(vm, list_slot) == WREN_TYPE_LIST,
            format("expected a list in slot %d", list_slot));
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

    static void wren_enforce(WrenVM* vm, lazy bool condition, lazy string message) {
        if (!condition) {
            // give wren an error
            wrenSetSlotString(vm, 0, message.toStringz);
            wrenAbortFiber(vm, 0);
        }
    }

    static string wren_expect_slot_string(WrenVM* vm, int slot) {
        wren_enforce(vm, wrenGetSlotType(vm, slot) == WREN_TYPE_STRING,
            format("expected a string in slot %d", slot));
        return wrenGetSlotString(vm, slot).to!string;
    }

    static string wren_expect_slot_nullable_string(WrenVM* vm, int slot) {
        if (wrenGetSlotType(vm, slot) == WREN_TYPE_NULL) {
            return null;
        }
        return wren_expect_slot_string(vm, slot);
    }

    static double wren_expect_slot_double(WrenVM* vm, int slot) {
        wren_enforce(vm, wrenGetSlotType(vm, slot) == WREN_TYPE_NUM,
            format("expected a number in slot %d", slot));
        return wrenGetSlotDouble(vm, slot);
    }

    static bool wren_expect_slot_bool(WrenVM* vm, int slot) {
        wren_enforce(vm, wrenGetSlotType(vm, slot) == WREN_TYPE_BOOL,
            format("expected a bool in slot %d", slot));
        return wrenGetSlotBool(vm, slot);
    }
}
