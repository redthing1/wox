module wox.build_host;

import wox.log;

class BuildHost {
    Logger log;
    
    this(Logger log) {
        this.log = log;
    }

    bool build(string buildfile_contents, string[] targets, string[] args) {

        return false;
    }
}
