module wox.foreign.argparser;

import wox.foreign.imports;
import wox.foreign.binder;

import pegged.grammar;

// args can be arguments, flags, or options
// arguments are just plain values
// options are --option-name or -o followed by a value
// flags are --flag-name or -
// note that both flags and options can use either single or double dashes
// we make our best effort to just guess based on conp_text
mixin(grammar(`
clioptsGrammar:
    ArgsList <- (Arg :Space?)*

    Arg <- Option / Flag / Argument

    Option <- DashedName :Space Value
    Flag <- DashedName
    Argument <- Value

    DashedName <- "--" Name / "-" Name
    Name <- AlphaNum+
    
    Value <- !"-" (!Space .)*
    AlphaNum <- [a-zA-Z0-9]
    Space <~ " "
`));

struct ParsedArgs {
    string[] arguments;
    string[string] options;
    string[] flags;

    string toString() {
        return format("ParsedArgs(arguments=%s, options=%s, flags=%s)",
            arguments, options, flags);
    }

    string arg(int index) @nogc @safe nothrow {
        if (index < arguments.length) {
            return arguments[index];
        }
        return null;
    }

    string opt(string name) @nogc @safe nothrow {
        if (name in options) {
            return options[name];
        }
        return null;
    }

    bool flag(string name) @nogc @safe nothrow {
        foreach (f; flags) {
            if (f == name) {
                return true;
            }
        }
        return false;
    }
}

struct ForeignWoxArgParser {
    // parse arbitrary list of arguments into key-value pairs
    static ParsedArgs parse(string raw_args) {
        ParsedArgs res;

        auto parseTree = clioptsGrammar(raw_args);
        // writefln("parse tree: %s", parseTree);

        string p_text(ParseTree pt) {
            return pt.input[pt.begin .. pt.end].dup;
        }

        void parse_to_result(ParseTree p) {
            // writefln("parse_to_result: walk: %s", p.name);
            switch (p.name) {
            case "clioptsGrammar.ArgsList":
                foreach (child; p.children)
                    parse_to_result(child);
                break;
            case "clioptsGrammar.Arg":
                parse_to_result(p.children[0]);
                break;
            case "clioptsGrammar.Option":
                auto option_name = p_text(p.children[0]);
                auto option_value = p_text(p.children[1]);
                res.options[option_name] = option_value;
                break;
            case "clioptsGrammar.Flag":
                auto flag_name = p_text(p.children[0]);
                res.flags ~= flag_name;
                break;
            case "clioptsGrammar.Argument":
                auto argument_value = p_text(p.children[0]);
                res.arguments ~= argument_value;
                break;
            default:
                break;
            }
        }

        parse_to_result(parseTree.children[0]);

        // writefln("parse result: %s", res);

        return res;
    }
}

@("argparser-test1")
unittest {
    auto res = ForeignWoxArgParser.parse(
        "bean.txt -v --quiet -i input.txt -o output.txt"
    );
    assert(res.arguments == ["bean.txt"], "arguments");
    assert(res.options == ["-i": "input.txt", "-o": "output.txt"], "options");
    assert(res.flags == ["-v", "--quiet"], "flags");
}
