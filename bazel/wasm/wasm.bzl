load("@proxy_wasm_cpp_sdk//bazel/wasm:wasm.bzl", "wasm_cc_binary")
load("@rules_rust//rust:rust.bzl", "rust_binary")

def _wasm_rust_transition_impl(settings, attr):
    return {
        "//command_line_option:platforms": "@rules_rust//rust/platform:wasm",
    }

wasm_rust_transition = transition(
    implementation = _wasm_rust_transition_impl,
    inputs = [],
    outputs = [
        "//command_line_option:platforms",
    ],
)

def _wasm_binary_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name)
    if ctx.attr.precompile:
        ctx.actions.run(
            executable = ctx.executable._compile_tool,
            arguments = [ctx.files.binary[0].path, out.path],
            outputs = [out],
            inputs = ctx.files.binary,
        )
    else:
        ctx.actions.run(
            executable = "cp",
            arguments = [ctx.files.binary[0].path, out.path],
            outputs = [out],
            inputs = ctx.files.binary,
        )

    return [DefaultInfo(files = depset([out]), runfiles = ctx.runfiles([out]))]

def _wasm_attrs(transition):
    return {
        "binary": attr.label(mandatory = True, cfg = transition),
        "precompile": attr.bool(default = False),
        # This is deliberately in target configuration to avoid compiling v8 twice.
        "_compile_tool": attr.label(default = "@envoy//test/tools/wee8_compile:wee8_compile_tool", executable = True, cfg = "target"),
        "_whitelist_function_transition": attr.label(default = "@bazel_tools//tools/whitelists/function_transition_whitelist"),
    }

wasm_rust_binary_rule = rule(
    implementation = _wasm_binary_impl,
    attrs = _wasm_attrs(wasm_rust_transition),
)

def envoy_wasm_cc_binary(name, deps = [], tags = [], **kwargs):
    wasm_cc_binary(
        name = name,
        deps = deps + ["@proxy_wasm_cpp_sdk//:proxy_wasm_intrinsics"],
        tags = tags + ["manual"],
        **kwargs
    )

def wasm_rust_binary(name, tags = [], **kwargs):
    wasm_name = "_wasm_" + name.replace(".", "_")
    kwargs.setdefault("visibility", ["//visibility:public"])

    rust_binary(
        name = wasm_name,
        edition = "2018",
        crate_type = "cdylib",
        out_binary = True,
        tags = ["manual"],
        **kwargs
    )

    wasm_rust_binary_rule(
        name = name,
        precompile = select({
            "@envoy//bazel:linux_x86_64": True,
            "//conditions:default": False,
        }),
        binary = ":" + wasm_name,
        tags = tags + ["manual"],
    )
