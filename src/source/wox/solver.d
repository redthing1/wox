module wox.solver;

import std.stdio;
import std.string;
import std.array;
import std.conv;
import std.typecons;
import std.exception : enforce;

import wox.models;

class SolverGraph {
    SolverNode[] roots;

    void add_root(SolverNode root) {
        roots ~= root;
    }
}

class SolverNode {
    Nullable!Footprint data;
    SolverNode parent = null;
    SolverNode[] children;

    this(Nullable!Footprint data) {
        this.data = data;
    }

    @get is_leaf() {
        return this.children.length == 0;
    }
}
