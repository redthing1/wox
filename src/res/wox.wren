// import "meta" for Meta

// general wox utils
class W {
    // cli args
    foreign static cliargs()                            // all cli args
    foreign static cliarg(name, default)                // string cli arg
    foreign static cliarg_int(name, default)            // int cli arg
    foreign static cliarg_bool(name, default)           // bool cli arg

    // path utils
    foreign static glob(pattern)                        // glob files
    foreign static ext_add(paths, ext)                  // add ext to paths
    foreign static ext_replace(paths, ext1, ext2)       // replace ext1 with ext2
    foreign static ext_remove(paths, ext_pattern)       // remove exts matching ext_pattern
}

// models
class Command {
    construct new(cmd) {
        _cmd = cmd
    }
    cmd { _cmd }
}

// data stuff for recipes: these don't actually execute but rather return data
class R {
    static c(cmd) {
        Command.new(cmd)
    }
}