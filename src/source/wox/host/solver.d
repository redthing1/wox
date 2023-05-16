module wox.host.solver;

import std.stdio;
import std.string;
import std.array;
import std.conv;
import std.typecons;
import std.file;
import std.container.dlist;
import std.exception : enforce;

import wox.log;
import wox.models;

class WoxSolver {
    class Graph {
        Node[] roots;

        void add_root(Node root) {
            roots ~= root;
        }
    }

    class Node {
        Footprint footprint;
        Recipe recipe;
        Node parent = null;
        Node[] children;

        int in_degree = 0;

        this(Footprint footprint) {
            this.footprint = footprint;
        }

        @get is_leaf() {
            return this.children.length == 0;
        }

        override string toString() const {
            return format("Node(%s > '%s')", this.footprint, this.recipe.name);
        }
    }

    Logger log;

    this(Logger log) {
        this.log = log;
    }

    Node[] toposort_graph(Graph solver_graph) {
        // topologically sort the graph iteratively using Kahn's algorithm
        int[Node] in_degree;

        bool[Node] visited;
        auto queue = DList!(Node)();
        foreach (node; solver_graph.roots) {
            in_degree[node] = 0;
            queue.insertBack(node);
        }

        while (!queue.empty) {
            auto node = queue.front;
            queue.removeFront;

            if (node in visited) {
                continue;
            }

            visited[node] = true;
            node.in_degree = in_degree[node];

            foreach (child; node.children) {
                // update in-degree of the child
                if (child !in in_degree) {
                    in_degree[child] = 0;
                }
                in_degree[child] += 1;
                child.in_degree = in_degree[child];
                if (child in visited) {
                    continue;
                }
                queue.insertBack(child);
            }
        }

        Node[] sorted_nodes;
        visited.clear();
        queue.clear();
        // queue the roots (they have in-degree 0)
        foreach (node; solver_graph.roots) {
            queue.insertBack(node);
        }

        while (!queue.empty) {
            auto node = queue.front;
            queue.removeFront;

            if (node in visited) {
                continue;
            }

            visited[node] = true;
            sorted_nodes ~= node;

            foreach (child; node.children) {
                // update in-degree of the child
                in_degree[child] -= 1;

                // if in-degree becomes 0, add it to queue
                if (in_degree[child] == 0) {
                    queue.insertBack(child);
                }
            }
        }
        enforce(sorted_nodes.length == visited.length, "graph has a cycle");

        // // print topologically sorted order
        // log.trace("topologically sorted order:");
        // foreach (node; sorted_nodes) {
        //     log.trace(" %s", node);
        // }

        return sorted_nodes;
    }

    Graph build_graph(Recipe[] goal_recipes, Recipe[] all_recipes) {
        // create a solver graph
        log.trace("creating solver graph");
        auto graph = new Graph();

        Nullable!Recipe find_recipe_to_build(Footprint footprint) {
            // find a recipe that says it can build this footprint
            log.trace(" finding recipe to build footprint %s", footprint);
            foreach (recipe; all_recipes) {
                // log.trace("  checking if recipe '%s' can build footprint %s", recipe.name, footprint);
                if (recipe.can_build_footprint(footprint)) {
                    log.trace("   recipe '%s' can build footprint %s", recipe.name, footprint);
                    return Nullable!Recipe(recipe);
                }
            }
            return Nullable!Recipe.init;
        }

        Footprint[] get_dependencies(Recipe recipe) {
            // get the immediate dependencies of this recipe
            return recipe.inputs;
        }

        struct RecipeWalk {
            Recipe recipe;
            Nullable!Recipe parent_recipe;
            Node[] parent_nodes;

            string toString() const {
                return format("RecipeWalk(recipe: '%s', parent: '%s', parent_nodes: %s)",
                    recipe.name,
                    parent_recipe.isNull ? "<null>" : parent_recipe.get.name,
                    parent_nodes
                );
            }
        }

        struct Edge {
            Node from;
            Node to;
        }

        auto recipe_queue = DList!RecipeWalk();
        bool[RecipeWalk] visited_walks;
        Node[Footprint] nodes_for_footprints;

        foreach (recipe; goal_recipes) {
            log.trace(" adding target recipe to solver graph: %s", recipe);
            recipe_queue.insertBack(RecipeWalk(recipe, Nullable!Recipe.init, []));
        }

        while (!recipe_queue.empty) {
            auto walk = recipe_queue.front;
            recipe_queue.removeFront;

            visited_walks[walk] = true;

            // process this walk
            // log.trace("processing recipe '%s'", walk.recipe.name);
            log.trace("processing recipe '%s' (parent: '%s')",
                walk.recipe.name,
                walk.parent_recipe.isNull ? "<null>" : walk.parent_recipe.get.name
            );

            // add graph nodes for the outputs
            Node[] curr_nodes;
            foreach (output; walk.recipe.outputs) {
                // find or create node for this output footprint
                Node output_node = null;
                if (output in nodes_for_footprints) {
                    // use existing node
                    output_node = nodes_for_footprints[output];
                    log.trace("  using node for output %s", output);
                } else {
                    // create a new node for this output
                    output_node = new Node(output);
                    output_node.recipe = walk.recipe;
                    log.trace("  created node for output %s", output);
                    nodes_for_footprints[output] = output_node;
                }

                // add this node to my parent's children
                if (!walk.parent_recipe.isNull) {
                    // since we are the child, our input is the parent's outputs
                    // so add this node to the parent node's children
                    foreach (parent_node; walk.parent_nodes) {
                        parent_node.children ~= output_node;
                        log.trace("   added edge %s -> %s", parent_node, output_node);
                    }
                } else {
                    // if the parent is null, this is a root node
                    graph.roots ~= output_node;
                    log.trace("   added root %s", output_node);
                }

                curr_nodes ~= output_node;
            }

            // add dependencies to the queue (from our inputs)
            foreach (dep; get_dependencies(walk.recipe)) {
                // find a recipe that can build this dependency
                auto maybe_dep_recipe = find_recipe_to_build(dep);
                if (maybe_dep_recipe.isNull) {
                    // couldn't find a recipe that can build this dependency
                    // see if it's a real file that exists
                    if (dep.reality == Footprint.Reality.File && std.file.exists(dep.name)) {
                        log.trace("  using real file %s", dep);
                        // this is a real file, which is a terminal
                        continue;
                    }
                    // otherwise, we don't know how to build this dependency
                    enforce(false, format("no recipe found that can build footprint %s", dep));
                    assert(0);
                }
                auto dep_walk = RecipeWalk(maybe_dep_recipe.get, Nullable!Recipe(walk.recipe), curr_nodes);

                if (dep_walk in visited_walks) {
                    // we've already visited this walk, so we don't need to add it to the queue
                    log.dbg("  already visited dependency walk %s", dep_walk);

                    continue;
                }

                // add it to the queue
                log.dbg("  adding dependency walk %s", dep_walk);
                recipe_queue.insertBack(dep_walk);
            }
        }

        return graph;
    }

    string dump_as_graphviz(Graph graph) {
        auto gv_builder = appender!string;

        gv_builder ~= "digraph {\n";

        // dfs through the graph and add nodes to the graphviz graph
        bool[Node] visited_nodes;
        auto node_stack = DList!Node();

        // queue initial nodes
        foreach (node; graph.roots) {
            // log.trace(" gv root %s", node);
            node_stack.insertBack(node);
        }

        while (!node_stack.empty) {
            auto node = node_stack.front;
            node_stack.removeFront;

            visited_nodes[node] = true;

            // add this node to the graph
            // log.dbg(" gv node %s", node);
            auto reality = node.footprint.reality;
            auto node_style = ["shape": "box"];
            switch (reality) {
            case Footprint.Reality.File:
                node_style["color"] = "green";
                break;
            case Footprint.Reality.Virtual:
                node_style["color"] = "blue";
                break;
            case Footprint.Reality.Unknown:
                node_style["color"] = "red";
                break;
            default:
                assert(0);
            }
            // gv.node(node, node_style);
            gv_builder ~= format("  \"%s\" [shape=box,color=%s];\n", node, node_style["color"]);

            // add this node's children to the queue
            foreach (child; node.children) {
                // this is a child, add an edge then queue it
                // log.dbg("  gv edge %s -> %s", node, child);
                // gv.edge(node, child, ["style": "solid"]);
                gv_builder ~= format("  \"%s\" -> \"%s\" [style=solid];\n", node, child);

                // if child is not visited, add it to the queue
                if (child !in visited_nodes) {
                    node_stack.insertBack(child);
                }
            }
        }

        gv_builder ~= "}\n";

        return gv_builder.data;
    }
}
