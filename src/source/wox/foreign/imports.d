module wox.foreign.imports;

public {
    import std.stdio;
    import std.string;
    import bc.string.string;
    import std.file;
    import std.path;
    import std.process;
    import wren.compiler;
    import wren.vm;
    import wren.common;
    import core.stdc.stdio;
    import core.stdc.string;
}

// util function for string comparison
bool eq(const(char)* a, const(char)* b) @nogc nothrow {
    return strcmp(a, b) == 0;
}
