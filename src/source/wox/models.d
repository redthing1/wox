module wox.models;

import std.stdio;
import std.string;
import std.array;
import std.conv;
import std.exception : enforce;
import typetips;

import wox.log;

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

struct StepInfo {
    enum Type {
        Command = 0,
        Log = 1,
    }

    Type type;
    string data;
    bool is_quiet = false;

    @property bool is_command() const {
        return type == Type.Command;
    }

    @property bool is_log() const {
        return type == Type.Log;
    }

    string toString() const {
        switch (type) {
        case Type.Command:
            return format("cmd(%s)", data);
        case Type.Log:
            return format("log(%s)", data);
        default:
            assert(0, "unknown step type");
        }
    }
}

struct Recipe {
    string name;
    Footprint[] inputs;
    Footprint[] outputs;
    StepInfo[] steps;

    string toString() const {
        auto sb = appender!string;

        sb ~= format("Recipe(%s) {\n", name);
        sb ~= format("  inputs: %s\n", inputs);
        sb ~= format("  outputs: %s\n", outputs);
        sb ~= format("  steps:");
        foreach (step; steps) {
            sb ~= format("\n    %s", step);
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

    Logger log;
    WrenExt wren_ext;

    this(Logger log, WrenVM* vm) {
        this.log = log;
        wren_ext = WrenExt(vm);
    }

    Optional!Recipe convert_recipe_from_wren(WrenHandle* recipe_h) {
        Recipe ret;

        // get name
        try {
            ret.name = wren_ext.call_prop_string(recipe_h, "name");
        } catch (Exception e) {
            log.err("failed to get name of recipe");
            return no!Recipe;
        }

        log.dbg("loading recipe '%s'", ret.name);

        auto inputs_list_h = wren_ext.call_prop_handle_list(recipe_h, "inputs");
        foreach (i, input_h; inputs_list_h) {
            try {
                auto maybe_footprint = convert_footprint_from_wren(input_h);
                ret.inputs ~= maybe_footprint.get;
            } catch (Exception e) {
                log.err("failed to load input %d of recipe '%s'", i, ret.name);
                return no!Recipe;
            }
        }

        // get outputs (which are a list of footprints)
        auto outputs_list_h = wren_ext.call_prop_handle_list(recipe_h, "outputs");
        foreach (i, output_h; outputs_list_h) {
            try {
                auto maybe_footprint = convert_footprint_from_wren(output_h);
                ret.outputs ~= maybe_footprint.get;
            } catch (Exception e) {
                log.err("failed to load output %d of recipe '%s'", i, ret.name);
                return no!Recipe;
            }
        }

        // get steps (which are a list of steps)
        auto steps_list_h = wren_ext.call_prop_handle_list(recipe_h, "steps");
        foreach (i, step_h; steps_list_h) {
            try {
                auto maybe_step = convert_step_from_wren(step_h);
                ret.steps ~= maybe_step.get;
            } catch (Exception e) {
                log.err("failed to load step %d of recipe '%s'", i, ret.name);
                return no!Recipe;
            }
        }

        // validate

        // name must not be null or empty
        if (ret.name is null || ret.name.length == 0) {
            log.err("recipe has no name: %s", ret);
            return no!Recipe;
        }

        return some(ret);
    }

    Optional!Footprint convert_footprint_from_wren(WrenHandle* footprint_h) {
        Footprint ret;

        ret.name = wren_ext.call_prop_nullable_string(footprint_h, "name");
        ret.reality = cast(Footprint.Reality) cast(int) wren_ext.call_prop_num(footprint_h, "reality");

        // validate

        // name must not be null or empty
        if (ret.name is null || ret.name.length == 0) {
            log.err("footprint has no name: %s", ret);
            return no!Footprint;
        }

        return some(ret);
    }

    Optional!StepInfo convert_step_from_wren(WrenHandle* step_h) {
        StepInfo ret;

        ret.type = cast(StepInfo.Type) cast(int) wren_ext.call_prop_num(step_h, "type");
        ret.data = wren_ext.call_prop_nullable_string(step_h, "data");
        ret.is_quiet = wren_ext.call_prop_bool(step_h, "quiet");

        // validate

        // data must not be null or empty
        if (ret.data is null || ret.data.length == 0) {
            log.err("step has no data: %s", ret);
            return no!StepInfo;
        }

        return some(ret);
    }
}
