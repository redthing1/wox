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
    foreign static ext_add(paths, ext)                      // add ext to paths
    foreign static ext_replace(paths, ext1, ext2)           // replace ext1 with ext2
    foreign static ext_remove(paths, ext_pattern)           // remove exts matching ext_pattern
    foreign static path_join(paths)                         // join paths
    foreign static path_split(path)                         // split path
    foreign static path_dirname(path)                       // dirname of path
    foreign static path_basename(path)                      // basename of path
    foreign static path_extname(path)                       // extname of path
    foreign static file_exists(path)                        // does file exist?

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
        for (i in range(0, min(seq1.length, seq2.length))) {
            ret.add([seq1[i], seq2[i]])
        }
        return ret
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

class Command {
    construct new(cmd) {
        _cmd = cmd
        _quiet = false
    }
    cmd { _cmd }
    quiet { _quiet }
    quiet=(value) { _quiet = value }
}

// data stuff for recipes: these don't actually execute but rather return data
class R {
    static c(cmd) {
        return Command.new(cmd)
    }
    static cq(cmd) {
        var command = c(cmd)
        command.quiet = true
        return command
    }
}