module wox.foreign.binder;

import wox.log;
import wox.foreign.imports;
import wox.foreign.argparser;

import wox.foreign.bind.w;

WoxForeignContext wox_context;

struct WoxForeignContext {
    Logger log;
    string cwd;
    std.string.string[] args;
    string[string] env;

    ParsedArgs parsed_args;

    void derive() {
        parsed_args = ForeignWoxArgParser.parse(args.join(" "));
    }
}

static class WoxBuildForeignBinder {
    static void initialize(WoxForeignContext context) {
        wox_context = context;
        wox_context.derive();
    }

    static WrenForeignMethodFn bindForeignMethod(WrenVM* vm, const(char)* module_,
        const(char)* className, bool isStatic, const(char)* signature) {
        auto pretty_sig = format("%s::%s.%s",
            module_.to!string, className.to!string, signature.to!string);

        wox_context.log.trace("[foreign binder] binding %s", pretty_sig);

        auto wox_utils_bind = BindForeignW.bind(
            vm, module_.to!string, className.to!string, signature.to!string, isStatic
        );
        if (wox_utils_bind !is null)
            return wox_utils_bind;

        wox_context.log.err("[foreign binder]   error: no binding found for %s", pretty_sig);

        return null;
    }
}
