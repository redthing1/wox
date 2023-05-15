module wox.foreign.binder;

import wox.log;
import wox.foreign.imports;
import wox.foreign.argparser;

import wox.foreign.wox_utils;

WoxForeignContext wox_context;

struct WoxForeignContext {
    std.string.string[] args;
    string[string] env;

    ParsedArgs parsed_args;

    void derive() {
        parsed_args = ForeignWoxArgParser.parse(args.join(" "));
    }
}

static class WoxBuildForeignBinder {
    static Logger log;

    static void initialize(Logger log, WoxForeignContext context) {
        this.log = log;
        wox_context = context;
        wox_context.derive();
    }

    static WrenForeignMethodFn bindForeignMethod(WrenVM* vm, const(char)* module_,
        const(char)* className, bool isStatic, const(char)* signature) {
        auto pretty_sig = format("%s::%s.%s",
            module_.to!string, className.to!string, signature.to!string);

        log.info("[foreign binder] binding %s", pretty_sig);

        auto wox_utils_bind = ForeignWoxUtils.bind(
            vm, module_.to!string, className.to!string, signature.to!string, isStatic
        );
        if (wox_utils_bind !is null)
            return wox_utils_bind;

        log.err("[foreign binder]   error: no binding found for %s", pretty_sig);

        return null;
    }
}
