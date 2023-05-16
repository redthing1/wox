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
        Virtual,
        Any
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
    bool is_quiet = false;
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
        return can_build_footprint(Footprint(target, Footprint.Reality.Any));
    }

    bool can_build_footprint(Footprint footprint) const {
        foreach (output; outputs) {
            if (output.name == footprint.name) {
                // we found a matching name, check if the reality matches
                // if the reality is any, then yeah sure
                if (footprint.reality == Footprint.Reality.Any) {
                    return true;
                }
                // otherwise, check if the realities match
                if (output.reality == footprint.reality) {
                    return true;
                }
            }
        }
        return false;
    }
}

struct ModelsFromWrenConverter {
    // convert models from wren handles
    import wren;
    import wox.host.meta;
    import wox.wren;

    WrenExt wren_ext;

    this(WrenVM* vm) {
        wren_ext = WrenExt(vm);
    }

    Recipe convert_recipe_from_wren(WrenHandle* recipe_h) {
        Recipe ret;

        // get name
        ret.name = wren_ext.call_prop_nullable_string(recipe_h, "name");

        auto inputs_list_h = wren_ext.call_prop_handle_list(recipe_h, "inputs");
        foreach (i, input_h; inputs_list_h) {
            ret.inputs ~= convert_footprint_from_wren(input_h);
        }

        // get outputs (which are a list of footprints)
        auto outputs_list_h = wren_ext.call_prop_handle_list(recipe_h, "outputs");
        foreach (i, output_h; outputs_list_h) {
            ret.outputs ~= convert_footprint_from_wren(output_h);
        }

        // get steps (which are a list of steps)
        auto steps_list_h = wren_ext.call_prop_handle_list(recipe_h, "steps");
        foreach (i, step_h; steps_list_h) {
            ret.steps ~= convert_step_from_wren(step_h);
        }

        return ret;
    }

    Footprint convert_footprint_from_wren(WrenHandle* footprint_h) {
        Footprint ret;

        ret.name = wren_ext.call_prop_nullable_string(footprint_h, "name");
        ret.reality = cast(Footprint.Reality) cast(int) wren_ext.call_prop_num(footprint_h, "reality");

        return ret;
    }

    CommandStep convert_step_from_wren(WrenHandle* step_h) {
        CommandStep ret;

        ret.cmd = wren_ext.call_prop_string(step_h, "cmd");
        ret.is_quiet = wren_ext.call_prop_bool(step_h, "quiet");

        return ret;
    }
}
