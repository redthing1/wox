module wox.wren.wren_ext;

import std.string;
import std.array;
import std.conv;
import std.exception : enforce;
import wren;

import wox.wren.wren_utils;

struct WrenExt {
    WrenVM* vm;
    this(WrenVM* vm) {
        this.vm = vm;
    }

    void call(WrenHandle* reciever, WrenHandle* call_handle) {
        wrenEnsureSlots(vm, 2);
        // put the reciever in slot 0
        wrenSetSlotHandle(vm, 0, reciever);
        // call
        auto call_result = wrenCall(vm, call_handle);
        enforce(call_result == WREN_RESULT_SUCCESS, "call failed");
        // result is in slot 0
    }

    WrenHandle* make_call_handle(string signature) {
        return wrenMakeCallHandle(vm, signature.toStringz);
    }

    WrenHandle* get_global_var_handle(string module_name, string var_name) {
        wrenEnsureSlots(vm, 1);
        wrenGetVariable(vm, module_name.toStringz, var_name.toStringz, 0);
        // make a handle and return it
        auto slot_handle = wrenGetSlotHandle(vm, 0);
        enforce(slot_handle != null, "slot handle is null");
        return slot_handle;
    }

    void get_ret_handle(WrenHandle* handle) {
        wrenEnsureSlots(vm, 1);
        wrenGetSlotHandle(vm, 0);
    }

    void release(WrenHandle* handle) {
        wrenReleaseHandle(vm, handle);
    }

    void release(WrenHandle*[] handle_list) {
        foreach (handle; handle_list) {
            release(handle);
        }
    }

    void call_prop(WrenHandle* receiver, string prop_name) {
        // get a call handle for the property
        auto call_handle = make_call_handle(prop_name);
        // call it
        call(receiver, call_handle);
        // release the call handle
        release(call_handle);
    }

    string call_prop_nullable_string(WrenHandle* receiver, string prop_name) {
        call_prop(receiver, prop_name);
        auto ret_type = wrenGetSlotType(vm, 0);
        enforce(ret_type == WREN_TYPE_NULL || ret_type == WREN_TYPE_STRING, "return type is not null or string");
        if (ret_type == WREN_TYPE_NULL) {
            return null;
        } else {
            return wrenGetSlotString(vm, 0).to!string;
        }
    }

    string call_prop_string(WrenHandle* receiver, string prop_name) {
        call_prop(receiver, prop_name);
        auto ret_type = wrenGetSlotType(vm, 0);
        enforce(ret_type == WREN_TYPE_STRING, "return type is not string");
        return wrenGetSlotString(vm, 0).to!string;
    }

    double call_prop_num(WrenHandle* receiver, string prop_name) {
        call_prop(receiver, prop_name);
        auto ret_type = wrenGetSlotType(vm, 0);
        enforce(ret_type == WREN_TYPE_NUM, "return type is not num");
        return wrenGetSlotDouble(vm, 0);
    }

    bool call_prop_bool(WrenHandle* receiver, string prop_name) {
        call_prop(receiver, prop_name);
        auto ret_type = wrenGetSlotType(vm, 0);
        enforce(ret_type == WREN_TYPE_BOOL, "return type is not bool");
        return wrenGetSlotBool(vm, 0);
    }

    WrenHandle*[] call_prop_handle_list(WrenHandle* receiver, string prop_name) {
        call_prop(receiver, prop_name);
        auto ret_type = wrenGetSlotType(vm, 0);
        enforce(ret_type == WREN_TYPE_LIST, "return type is not list");
        wrenEnsureSlots(vm, 2);
        auto handle_list = WrenUtils.wren_read_handle_list(vm, 0, 1);
        return handle_list;
    }
}
