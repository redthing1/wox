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
    Footprint footprint;
    Recipe recipe;
    SolverNode parent = null;
    SolverNode[] children;

    int in_degree = 0;

    this(Footprint footprint) {
        this.footprint = footprint;
    }

    @get is_leaf() {
        return this.children.length == 0;
    }

    override string toString() const {
        return format("SolverNode(%s > '%s')", this.footprint, this.recipe.name);
    }
}
