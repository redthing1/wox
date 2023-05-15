module wox.foreign.binder;

import wox.log;
import wox.foreign.imports;

import wox.foreign.wox_utils;

WoxForeignContext wox_context;

struct WoxForeignContext {
    Logger log;
    string[] args;
    string[string] env;
}

static class WoxBuildForeignBinder {
    static void initialize(WoxForeignContext context) {
        wox_context = context;
    }

    // static void myFun(WrenVM* vm) @nogc nothrow {
    //     double a = wrenGetSlotDouble(vm, 1);
    //     double b = wrenGetSlotDouble(vm, 2);
    //     double c = wrenGetSlotDouble(vm, 3);

    //     printf("Called with %f, %f, %f\n", a, b, c);
    // }

    static WrenForeignMethodFn bindForeignMethod(WrenVM* vm, const(char)* module_,
        const(char)* className, bool isStatic, const(char)* signature) @nogc nothrow {
        // create a string to contain the Module::Class.Method signature
        char[1024] pretty_signature;
        snprintf(pretty_signature.ptr, pretty_signature.length, "%s::%s.%s", module_, className, signature);
        pretty_signature[cast(int) pretty_signature.length - 1] = '\0';

        printf("[foreign binder] binding %s\n", pretty_signature.ptr);

        // if (strcmp(signature, "myfun_(_,_,_)") == 0)
        //     return &myFun;

        auto wox_utils_bind = ForeignWoxUtils.bind(vm, module_, className, isStatic, signature);
        if (wox_utils_bind !is null)
            return wox_utils_bind;

        printf("[foreign binder]   error: no binding found for %s\n", pretty_signature.ptr);

        return null;
    }
}
