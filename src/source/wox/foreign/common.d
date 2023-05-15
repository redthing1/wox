module wox.foreign.common;

import wox.foreign.imports;
import wox.foreign.binder;

static struct ForeignWoxCommon {
    static string promote_cstring(const(char*) cstr, char[] buffer) {
        auto str_len = strlen(cstr);
        // auto str = new char[str_len];
        assert(buffer.length >= str_len, "buffer too small");

        for (auto i = 0; i < str_len; i++) {
            buffer[i] = cstr[i];
        }

        return cast(string) buffer;
    }
}
