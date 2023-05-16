// import "meta" for Meta

// general wox utils
class W {
    // cli args
    foreign static cliopts()                            // all cli args
    foreign static cliopt(name, default)                // string cli opt
    foreign static cliopt_int(name, default)            // int cli opt
    foreign static cliopt_bool(name, default)           // bool cli opt

    // path utils
    foreign static glob(pattern)                        // glob files
    foreign static ext_add(paths, ext)                  // add ext to paths
    foreign static ext_replace(paths, ext1, ext2)       // replace ext1 with ext2
    foreign static ext_remove(paths, ext_pattern)       // remove exts matching ext_pattern
    foreign static path_join(paths)                     // join paths
    foreign static path_split(path)                     // split path
    foreign static path_dirname(path)                   // dirname of path
    foreign static path_basename(path)                  // basename of path
    foreign static path_extname(path)                   // extname of path

    // logging
    foreign static log_err(msg)                         // log err msg
    foreign static log_wrn(msg)                         // log warn msg
    foreign static log_inf(msg)                         // log info msg
    foreign static log_trc(msg)                         // log trace msg
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