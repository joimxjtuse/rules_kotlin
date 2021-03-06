"""Kotlin Rules

### Setup

Add the following snippet to your `WORKSPACE` file:

```bzl
git_repository(
    name = "io_bazel_rules_kotlin",
    remote = "https://github.com/bazelbuild/rules_kotlin.git",
    commit = "<COMMIT_HASH>",
)
load("@io_bazel_rules_kotlin//kotlin:kotlin.bzl", "kotlin_repositories")
kotlin_repositories(kotlin_release_version = "1.2.10")
```

To enable persistent worker support, add the following to the appropriate `bazelrc` file:

```
build --strategy=KotlinCompile=worker
test --strategy=KotlinCompile=worker
```


### Standard Libraries

The Kotlin libraries that are bundled in a kotlin release should be used with the rules. After enabling the repository
the following Kotlin Libraries are made available in the kotlin compiler repository -- `com_github_jetbrains_kotlin`:

* `stdlib`
* `stdlib-jdk7`,
* `stdlib-jdk8`,
* `test`,
* `reflect`.

So if you needed to add reflect as a dep use the following label `@com_github_jetbrains_kotlin//:reflect`.

### Caveats

* The compiler is currently not configurable [issue](https://github.com/hsyed/rules_kotlin/issues/3).
* The compiler is harded to target jdk8 and language and api levels "1.2" [issue](https://github.com/hsyed/rules_kotlin/issues/3).
* `stdlib`, `stdlib-jdk7` and `stdlib-jdk8` are added by default to any compile operation [issue](https://github.com/hsyed/rules_kotlin/issues/3).
"""
# This file is the main import -- it shouldn't grow out of hand the reason it contains so much allready is due to the limitations of skydoc.

########################################################################################################################
# Common Definitions
########################################################################################################################

load("//kotlin/rules:defs.bzl", "KOTLIN_REPO_ROOT")

# The files types that may be passed to the core Kotlin compile rule.
_kt_compile_filetypes = FileType([".kt"])

_jar_filetype = FileType([".jar"])

_srcjar_filetype = FileType([
    ".jar",
    "-sources.jar",
])

########################################################################################################################
# Rule Attributes
########################################################################################################################
_implicit_deps = {
    "_kotlin_compiler_classpath": attr.label_list(
        allow_files = True,
        default = [
            Label("@" + KOTLIN_REPO_ROOT + "//:compiler"),
            Label("@" + KOTLIN_REPO_ROOT + "//:reflect"),
            Label("@" + KOTLIN_REPO_ROOT + "//:script-runtime"),
        ],
    ),
    "_kotlinw": attr.label(
        default = Label("//kotlin/workers/compilers/jvm"),
        executable = True,
        cfg = "host",
    ),
    # The kotlin runtime
    "_kotlin_runtime": attr.label(
        single_file = True,
        default = Label("@" + KOTLIN_REPO_ROOT + "//:runtime"),
    ),
    # The kotlin stdlib
    "_kotlin_std": attr.label_list(default = [
        Label("@" + KOTLIN_REPO_ROOT + "//:stdlib"),
        Label("@" + KOTLIN_REPO_ROOT + "//:stdlib-jdk7"),
        Label("@" + KOTLIN_REPO_ROOT + "//:stdlib-jdk8"),
    ]),
    "_kotlin_reflect": attr.label(
        single_file = True,
        default =
            Label("@" + KOTLIN_REPO_ROOT + "//:reflect"),
    ),
    "_singlejar": attr.label(
        executable = True,
        cfg = "host",
        default = Label("@bazel_tools//tools/jdk:singlejar"),
        allow_files = True,
    ),
    "_zipper": attr.label(
        executable = True,
        cfg = "host",
        default = Label("@bazel_tools//tools/zip:zipper"),
        allow_files = True,
    ),
    "_java": attr.label(
        executable = True,
        cfg = "host",
        default = Label("@bazel_tools//tools/jdk:java"),
        allow_files = True,
    ),
    "_java_stub_template": attr.label(default = Label("@kt_java_stub_template//file")),
}

_common_attr = dict(_implicit_deps.items() + {
    "srcs": attr.label_list(
        default = [],
        allow_files = _kt_compile_filetypes,
    ),
    # only accept deps which are java providers.
    "deps": attr.label_list(),
    "runtime_deps": attr.label_list(default = []),
    # Add debugging info for any rules.
    #    "verbose": attr.int(default = 0),
    #    "opts": attr.string_dict(),
    # Advanced options
    #    "x_opts": attr.string_list(),
    # Plugin options
    #    "plugin_opts": attr.string_dict(),
    "resources": attr.label_list(
        default = [],
        allow_files = True,
    ),
    "resource_strip_prefix": attr.string(default = ""),
    "resource_jars": attr.label_list(default = []),
    # Other args for the compiler
}.items())

_runnable_common_attr = dict(_common_attr.items() + {
    "data": attr.label_list(
        allow_files = True,
        cfg = "data",
    ),
    "jvm_flags": attr.string_list(
        default = [],
    ),
}.items())

########################################################################################################################
# Outputs: All the outputs produced by the various rules are modelled here.
########################################################################################################################
_common_outputs = dict(
    jar = "%{name}.jar",
    srcjar = "%{name}-sources.jar",
)

_binary_outputs = dict(_common_outputs.items() + {
#    "wrapper": "%{name}_wrapper.sh",
}.items())

########################################################################################################################
# Repositories
########################################################################################################################
load(
    "//kotlin:kotlin_compiler_repositories.bzl",
    "KOTLIN_CURRENT_RELEASE",
    _kotlin_compiler_repository = "kotlin_compiler_repository",
)

def kotlin_repositories(
    kotlin_release_version=KOTLIN_CURRENT_RELEASE
):
    """Call this in a WORKSPACE to setup the Kotlin rules.

    Args:
      kotlin_release_version: The kotlin compiler release version. If this is not set the latest release version is
      chosen by default.
    """
    _kotlin_compiler_repository(kotlin_release_version)

########################################################################################################################
# Simple Rules:
########################################################################################################################
load(
    "//kotlin/rules:rules.bzl",
    _kotlin_binary_impl = "kotlin_binary_impl",
    _kotlin_junit_test_impl = "kotlin_junit_test_impl",
    _kotlin_library_impl = "kotlin_library_impl",
)

kotlin_library = rule(
    attrs = dict(_common_attr.items() + {"exports": attr.label_list()}.items()),
    outputs = _common_outputs,
    implementation = _kotlin_library_impl,
)

"""This rule compiles and links Kotlin sources into a .jar file.
Args:
  srcs: The list of source files that are processed to create the target.
  exports: Exported libraries.

    Listing rules here will make them available to parent rules, as if the parents explicitly depended on these rules.
    This is not true for regular (non-exported) deps.
  resources: A list of data files to include in a Java jar.
  resource_strip_prefix: The path prefix to strip from Java resources.
  resource_jars: Set of archives containing Java resources.If specified, the contents of these jars are merged into the
    output jar.
  runtime_deps: Libraries to make available to the final binary or test at runtime only. Like ordinary deps, these will
    appear on the runtime classpath, but unlike them, not on the compile-time classpath.
  data: The list of files needed by this rule at runtime. See general comments about `data` at [Attributes common to all build rules](https://docs.bazel.build/versions/master/be/common-definitions.html#common-attributes).
  deps: A list of dependencies of this rule.See general comments about `deps` at [Attributes common to all build rules](https://docs.bazel.build/versions/master/be/common-definitions.html#common-attributes).
"""

kotlin_binary = rule(
    attrs = dict(_runnable_common_attr.items() + {"main_class": attr.string(mandatory = True)}.items()),
    executable = True,
    outputs = _binary_outputs,
    implementation = _kotlin_binary_impl,
)

"""Builds a Java archive ("jar file"), plus a wrapper shell script with the same name as the rule. The wrapper shell
script uses a classpath that includes, among other things, a jar file for each library on which the binary depends.

Args:
  main_class: Name of class with main() method to use as entry point.
  jvm_flags: A list of flags to embed in the wrapper script generated for running this binary. Note: does not yet support
    make variable substition.
"""

kotlin_test = rule(
    attrs = dict(_runnable_common_attr.items() + {
        "_bazel_test_runner": attr.label(
            default = Label("@bazel_tools//tools/jdk:TestRunner_deploy.jar"),
            allow_files = True,
        ),
        "test_class": attr.string(),
        #      "main_class": attr.string(),
    }.items()),
    executable = True,
    outputs = _binary_outputs,
    test = True,
    implementation = _kotlin_junit_test_impl,
)

"""Setup a simple kotlin_test.
Args:
  test_class: The Java class to be loaded by the test runner.
"""
