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
    alias NodeData = Footprint;
    NodeData data;
    SolverNode parent = null;
    SolverNode[] children;

    this(NodeData data) {
        this.data = data;
    }

    @get is_leaf() {
        return this.children.length == 0;
    }

    override string toString() const {
        return format("SolverNode(%s)", this.data);
    }
}
