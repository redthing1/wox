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

    // logging
    foreign static log_err(msg)                             // log err msg
    foreign static log_wrn(msg)                             // log warn msg
    foreign static log_inf(msg)                             // log info msg
    foreign static log_trc(msg)                             // log trace msg
    foreign static log_dbg(msg)                             // log debug msg

    // shell
    foreign static shell(cmd)                               // run shell cmd

    // recipes
    // foreign static recipe(inputs, outputs, steps)           // recipe
    // foreign static recipe(name, inputs, outputs, steps)     // named recipe
    // foreign static virtual_recipe(name, inputs, steps)      // virtual recipe

    static recipe(inputs, outputs, steps) {
        return Recipe.new(null, as_footprints_(inputs), as_footprints_(outputs), steps)
    }

    static recipe(name, inputs, outputs, steps) {
        return Recipe.new(name, as_footprints_(inputs), as_footprints_(outputs), steps)
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
    }
    cmd { _cmd }
}

// data stuff for recipes: these don't actually execute but rather return data
class R {
    static c(cmd) {
        return Command.new(cmd)
    }
}