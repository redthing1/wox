module wox.foreign.imports;

public {
    import std.stdio;
    import std.string;
    import std.file;
    import std.path;
    import std.process;
    import core.stdc.stdio;
    import core.stdc.string;
    import core.stdc.stdlib;

    import wren.compiler;
    import wren.vm;
    import wren.common;
    

    import bc.string.string;
    import tanya.containers;
}

// util function for string comparison
bool eq(const(char)* a, const(char)* b) @nogc nothrow {
    return strcmp(a, b) == 0;
}
