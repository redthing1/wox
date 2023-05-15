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
CliArgsGrammar:
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
}

struct ForeignWoxArgParser {
    // parse arbitrary list of arguments into key-value pairs
    static ParsedArgs parse(string raw_args) {
        ParsedArgs res;

        auto parseTree = CliArgsGrammar(raw_args);
        // writefln("parse tree: %s", parseTree);

        string p_text(ParseTree pt) {
            return pt.input[pt.begin .. pt.end].dup;
        }

        void parse_to_result(ParseTree p) {
            // writefln("parse_to_result: walk: %s", p.name);
            switch (p.name) {
            case "CliArgsGrammar.ArgsList":
                foreach (child; p.children)
                    parse_to_result(child);
                break;
            case "CliArgsGrammar.Arg":
                parse_to_result(p.children[0]);
                break;
            case "CliArgsGrammar.Option":
                auto option_name = p_text(p.children[0]);
                auto option_value = p_text(p.children[1]);
                res.options[option_name] = option_value;
                break;
            case "CliArgsGrammar.Flag":
                auto flag_name = p_text(p.children[0]);
                res.flags ~= flag_name;
                break;
            case "CliArgsGrammar.Argument":
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
