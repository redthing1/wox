module wox.models;

import std.stdio;
import std.string;
import std.array;
import std.conv;
import std.exception : enforce;

struct Footprint {
    enum Reality {
        Unknown,
        File,
        Virtual
    }

    string name;
    Reality reality;

    string toString() const {
        static immutable short_reality = ["U", "F", "V"];
        return format("%s:%s", name, short_reality[cast(int) reality]);
    }
}

struct CommandStep {
    string cmd;
}

struct Recipe {
    string name;
    Footprint[] inputs;
    Footprint[] outputs;
    CommandStep[] steps;

    string toString() const {
        auto sb = appender!string;

        sb ~= format("Recipe(%s) {\n", name);
        sb ~= format("  inputs: %s\n", inputs);
        sb ~= format("  outputs: %s\n", outputs);
        sb ~= format("  steps:");
        foreach (step; steps) {
            sb ~= format("\n    %s", step.cmd);
        }
        sb ~= "\n}";

        return sb.data;
    }

    bool can_build_target(string target) const {
        foreach (output; outputs) {
            if (output.name == target) {
                return true;
            }
        }
        return false;
    }
}

struct ModelsFromWren {
    // convert models from wren handles
    import wren;
    import wox.wren_integration;
    import wox.wren_utils;

    static Recipe convert_recipe_from_wren(WrenVM* vm, WrenHandle* recipe_h) {
        Recipe ret;

        wrenEnsureSlots(vm, 4);

        // get class definition of Recipe
        wrenGetVariable(vm, WOX_MODULE, "Recipe", 0);
        auto recipe_type_h = wrenGetSlotHandle(vm, 0);

        // get name property
        auto name_prop_h = wrenMakeCallHandle(vm, "name");
        wrenSetSlotHandle(vm, 0, recipe_h);
        auto name_prop_call_result = wrenCall(vm, name_prop_h);
        enforce(name_prop_call_result == WREN_RESULT_SUCCESS, "failed to get name property of recipe");
        if (wrenGetSlotType(vm, 0) == WREN_TYPE_NULL) {
            ret.name = null;
        } else {
            enforce(wrenGetSlotType(vm, 0) == WREN_TYPE_STRING, "return value of name property is not a string");
            ret.name = wrenGetSlotString(vm, 0).to!string;
        }

        // get inputs (which are a list of footprints)
        auto inputs_prop_h = wrenMakeCallHandle(vm, "inputs");
        wrenSetSlotHandle(vm, 0, recipe_h);
        auto inputs_prop_call_result = wrenCall(vm, inputs_prop_h);
        enforce(inputs_prop_call_result == WREN_RESULT_SUCCESS, "failed to get inputs property of recipe");
        enforce(wrenGetSlotType(vm, 0) == WREN_TYPE_LIST, "return value of inputs property is not a list");
        auto inputs_list_h = WrenUtils.wren_read_handle_list(vm, 0, 1);
        foreach (i, input_h; inputs_list_h) {
            ret.inputs ~= convert_footprint_from_wren(vm, input_h);
        }

        // get outputs (which are a list of footprints)
        auto outputs_prop_h = wrenMakeCallHandle(vm, "outputs");
        wrenSetSlotHandle(vm, 0, recipe_h);
        auto outputs_prop_call_result = wrenCall(vm, outputs_prop_h);
        enforce(outputs_prop_call_result == WREN_RESULT_SUCCESS, "failed to get outputs property of recipe");
        enforce(wrenGetSlotType(vm, 0) == WREN_TYPE_LIST, "return value of outputs property is not a list");
        auto outputs_list_h = WrenUtils.wren_read_handle_list(vm, 0, 1);
        foreach (i, output_h; outputs_list_h) {
            ret.outputs ~= convert_footprint_from_wren(vm, output_h);
        }

        // get steps (which are a list of steps)
        auto steps_prop_h = wrenMakeCallHandle(vm, "steps");
        wrenSetSlotHandle(vm, 0, recipe_h);
        auto steps_prop_call_result = wrenCall(vm, steps_prop_h);
        enforce(steps_prop_call_result == WREN_RESULT_SUCCESS, "failed to get steps property of recipe");
        enforce(wrenGetSlotType(vm, 0) == WREN_TYPE_LIST, "return value of steps property is not a list");
        auto steps_list_h = WrenUtils.wren_read_handle_list(vm, 0, 1);
        foreach (i, step_h; steps_list_h) {
            ret.steps ~= convert_step_from_wren(vm, step_h);
        }

        // writefln("converted recipe:\n%s", ret);

        return ret;
    }

    static Footprint convert_footprint_from_wren(WrenVM* vm, WrenHandle* footprint_h) {
        Footprint ret;

        wrenEnsureSlots(vm, 4);

        // get name property
        auto name_prop_h = wrenMakeCallHandle(vm, "name");
        wrenSetSlotHandle(vm, 0, footprint_h);
        auto name_prop_call_result = wrenCall(vm, name_prop_h);
        enforce(name_prop_call_result == WREN_RESULT_SUCCESS, "failed to get name property of footprint");
        if (wrenGetSlotType(vm, 0) == WREN_TYPE_NULL) {
            ret.name = null;
        } else {
            enforce(wrenGetSlotType(vm, 0) == WREN_TYPE_STRING,
                format("return value of name property is not a string, but %s", wrenGetSlotType(vm, 0)));
            ret.name = wrenGetSlotString(vm, 0).to!string;
        }

        // get reality property
        auto reality_prop_h = wrenMakeCallHandle(vm, "reality");
        wrenSetSlotHandle(vm, 0, footprint_h);
        auto reality_prop_call_result = wrenCall(vm, reality_prop_h);
        enforce(reality_prop_call_result == WREN_RESULT_SUCCESS, "failed to get reality property of footprint");
        enforce(wrenGetSlotType(vm, 0) == WREN_TYPE_NUM, "return value of reality property is not a number");
        ret.reality = cast(Footprint.Reality) cast(int) wrenGetSlotDouble(vm, 0);

        // writefln("converted footprint: %s", ret);

        return ret;
    }

    static CommandStep convert_step_from_wren(WrenVM* vm, WrenHandle* step_h) {
        CommandStep ret;

        wrenEnsureSlots(vm, 4);

        // get cmd property
        auto cmd_prop_h = wrenMakeCallHandle(vm, "cmd");
        wrenSetSlotHandle(vm, 0, step_h);
        auto cmd_prop_call_result = wrenCall(vm, cmd_prop_h);
        enforce(cmd_prop_call_result == WREN_RESULT_SUCCESS, "failed to get cmd property of step");
        enforce(wrenGetSlotType(vm, 0) == WREN_TYPE_STRING, "return value of cmd property is not a string");
        ret.cmd = wrenGetSlotString(vm, 0).to!string;

        // writefln("converted step: %s", ret);

        return ret;
    }
}
