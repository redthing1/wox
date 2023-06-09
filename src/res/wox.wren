import "meta" for Meta

// general wox utils
class W {
    // cli args and environment vars
    foreign static cliopts()                                // all cli args
    foreign static cliopt(name, default)                    // string cli opt
    foreign static cliopt_int(name, default)                // int cli opt
    foreign static cliopt_bool(name, default)               // bool cli opt
    foreign static env(name, default)                       // string env var

    // path utils
    foreign static glob(pattern)                            // glob files
    foreign static path_join(paths)                         // join paths
    foreign static path_split(path)                         // split path
    foreign static path_dirname(path)                       // dirname of path
    foreign static path_basename(path)                      // basename of path
    foreign static path_extname(path)                       // extname of path
    foreign static file_exists(path)                        // does file exist?
    foreign static abspath(path)                            // absolute path

    static replace_many(list, from_str, to_str) {
        return list.map{|x| x.replace(from_str, to_str)}.toList
    }
    static exts_replace(paths, from_str, to_str) {
        return replace_many(paths, from_str, to_str)
    }
    static last_index_of(path) {
        var last_dot_ix = -1
        for (i in path.count-1..0) {
            if (path[i] == ".") {
                last_dot_ix = i
                break
            }
        }
        return last_dot_ix
    }
    static ext_split(path) {
        var dot_ix = last_index_of(path)
        var path_noext = path[0...dot_ix]
        var path_ext = path[dot_ix..-1]
        return [path_noext, path_ext]
    }
    static ext_remove(path) {
        var dot_ix = last_index_of(path)
        return path[0...dot_ix]
    }
    static exts_remove(paths) {
        return paths.map{|x| ext_remove(x)}.toList
    }
    static ext_add(path, ext) {
        return path + ext
    }
    static exts_add(paths, ext) {
        return paths.map{|x| ext_add(x, ext)}.toList
    }
    static abspaths(paths) {
        return paths.map{|x| abspath(x)}.toList
    }

    // logging
    foreign static log_err(msg)                             // log err msg
    foreign static log_wrn(msg)                             // log warn msg
    foreign static log_inf(msg)                             // log info msg
    foreign static log_trc(msg)                             // log trace msg
    foreign static log_dbg(msg)                             // log debug msg

    // shell
    foreign static shell(cmd)                               // run shell cmd

    // misc utils
    foreign static join(list, sep)                          // join list with sep
    static join(list) { join(list, " ") }                   // join list with default sep

    static zip(seq1, seq2) {
        var ret = []
        for (i in 0...(seq1.count.min(seq2.count))) {
            ret.add([seq1[i], seq2[i]])
        }
        return ret
    }
    static flatten(list_list) {
        var ret = []
        for (list in list_list) {
            ret = ret + list
        }
        return ret
    }

    static lines(str) {
        if (str.count == 0) {
            return []
        }
        return str.split("\n")
    }

    static fail() {
        Fiber.abort("aborted")
    }

    // recipes
    // foreign static recipe(inputs, outputs, steps)           // recipe
    // foreign static recipe(name, inputs, outputs, steps)     // named recipe
    // foreign static virtual_recipe(name, inputs, steps)      // virtual recipe

    // static recipe(inputs, outputs, steps) {
    //     return recipe(null, inputs, outputs, steps)
    // }

    static recipe(name, inputs, outputs, steps) {
        var footprint_inputs = as_footprints_(inputs)
        var footprint_outputs = as_footprints_(outputs)

        // add implicit virtual output for the recipe name
        footprint_outputs.add(Footprint.new(name, FootprintReality.virtual))

        return Recipe.new(
            name,
            footprint_inputs,
            footprint_outputs,
            steps
        )
    }

    static virtual_recipe(name, inputs, steps) {
        var virtual_output = name
        return Recipe.new(
            name,
            as_footprints_(inputs),
            as_footprints_([virtual_output], FootprintReality.virtual),
            steps
        )
    }

    static meta_recipe(name, input_recipes) {
        // inputs will be other recipes, and thus virtual
        var input_targets = []
        for (input_recipe in input_recipes) {
            input_targets.add(input_recipe.name)
        }
        var virtual_output = name
        return Recipe.new(
            name,
            as_footprints_(input_targets, FootprintReality.virtual),
            as_footprints_([virtual_output], FootprintReality.virtual),
            []
        )
    }

    static as_footprints_(names) {
        return as_footprints_(names, FootprintReality.unknown)
    }

    static as_footprints_(names, reality) {
        var footprints = []
        for (name in names) {
            footprints.add(Footprint.new(name, reality))
        }
        return footprints
    }
    static relative_path(base_path, path) {
        return path_join([base_path, path])
    }
    static relative_paths(base_path, paths) {
        return paths.map{|x| relative_path(base_path, x)}.toList
    }
    // static make_footprint_relative(base_path, footprint) {
    //     return Footprint.new(
    //         relative_path(base_path, footprint.name),
    //         footprint.reality
    //     )
    // }
    // static make_recipe_relative(base_path, recipe) {
    //     var inputs = recipe.inputs.map{|x| make_footprint_relative(base_path, x)}.toList
    //     var outputs = recipe.outputs.map{|x| make_footprint_relative(base_path, x)}.toList
    //     return Recipe.new(recipe.name, inputs, outputs, recipe.steps)
    // }
    // static make_recipes_relative(base_path, recipes) {
    //     return recipes.map{|x| make_recipe_relative(base_path, x)}.toList
    // }
}

// models
class FootprintReality {
    static unknown { 0 }
    static file { 1 }
    static virtual { 2 }
}

// represents inputs/outputs, can be real files or virtual names
class Footprint {
    construct new(name, reality) {
        _name = name
        _reality = reality
    }

    name { _name }
    reality { _reality }
}

// represents a way to create outputs from inputs by following steps
class Recipe {
    construct new(name, inputs, outputs, steps) {
        _name = name
        _inputs = inputs
        _outputs = outputs
        _steps = steps
    }

    name { _name }
    inputs { _inputs }
    outputs { _outputs }
    steps { _steps }
}

var STEP_TYPE_RUN = 0
var STEP_TYPE_LOG = 1

class StepInfo {
    construct new(type, data) {
        _type = type
        _data = data
        _quiet = false
    }
    type { _type }
    data { _data }
    quiet { _quiet }
    quiet=(value) { _quiet = value }
}

// data stuff for recipes: these don't actually execute but rather return data
class R {
    static c(cmd) {
        return StepInfo.new(STEP_TYPE_RUN, cmd)
    }
    static cq(cmd) {
        var command = c(cmd)
        command.quiet = true
        return command
    }

    // alias for c
    static run(cmd) {
        return c(cmd)
    }

    static log(msg) {
        return StepInfo.new(STEP_TYPE_LOG, msg)
    }
}