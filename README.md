
# wox

**wox** is a highly flexible recipe build system, inspired by [make](https://www.gnu.org/software/make/manual/make.html). wox is also based on learning from other build systems inspired by make such as [knit](https://github.com/zyedidia/knit).

wox is designed to provide all the power and flexibility of arbitrary recipe-based builds, while at the same time addressing make's shortcomings.

## features

+ build scripts are written in [wren](https://wren.io/), and declaratively export a set of recipes
+ recipes with multiple outputs are supported
+ better change detection with virtual targets
+ detect changes in recipe steps when cache is enabled (`-k`)
+ multithreaded recipe building by default

## see a real example

```wren
import "wox" for W, R

var TARGET = "./hello"

var cc = W.cliopt("-cc", "gcc")
var cflags = ["-Wall", "-std=c11"]

var srcs = W.glob("./*.c")
var objs = W.exts_replace(srcs, ".c", ".o")
var src_obj_pairs = W.zip(srcs, objs)

var obj_recipes = src_obj_pairs.map { |x|
    W.recipe(x[1], [x[0]], [x[1]], 
        [ R.c("%(cc) %(W.join(cflags)) -c %(x[0]) -o %(x[1])") ]
    )
}

var main_recipe = W.recipe("main", objs, [TARGET], 
    [ R.c("%(cc) %(W.join(cflags)) %(W.join(objs)) -o %(TARGET)") ]
)
var clean_recipe = W.virtual_recipe("clean", [],
    [ R.c("rm -f %(W.join(objs)) %(TARGET)") ]
)
var all_recipe = W.meta_recipe("all", [main_recipe])

var BUILD_RECIPES = obj_recipes + [main_recipe, clean_recipe, all_recipe]

class Build {
    static recipes { BUILD_RECIPES }
    static default_recipe { "all" }
}
```

## build

the recommended way to build is with [redbuild](https://github.com/redthing1/redbuild2).

```sh
redbuild build
```

alternatively, build using the D toolchain:
```sh
cd src
dub build -b release
```

## usage

generally, wox can be called similarly to make:

```sh
wox [options] [targets...]
```
