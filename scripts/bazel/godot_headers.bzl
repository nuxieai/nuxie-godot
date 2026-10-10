"""Generate the pinned engine headers as declared Apple compiler inputs."""

load("@apple_support//lib:apple_support.bzl", "apple_support")

def _header_platform_impl(_settings, attr):
    return {"//command_line_option:platforms": [str(attr.header_platform)]}

_header_platform = transition(
    implementation = _header_platform_impl,
    inputs = [],
    outputs = ["//command_line_option:platforms"],
)

def _headers_impl(ctx):
    headers = ctx.actions.declare_directory(ctx.label.name)
    args = ctx.actions.args()
    args.add("--archive", ctx.file.archive)
    args.add("--output", headers.path)
    args.add("--version", ctx.attr.version)
    args.add("--scons", ctx.executable._scons)
    apple_support.run(
        actions = ctx.actions,
        apple_fragment = ctx.fragments.apple,
        xcode_config = ctx.attr._xcode_config[apple_common.XcodeVersionConfig],
        executable = ctx.executable._generator,
        arguments = [args],
        inputs = [ctx.file.archive],
        tools = [ctx.attr._scons[DefaultInfo].files_to_run],
        outputs = [headers],
        mnemonic = "GodotIosHeaders",
    )
    return [DefaultInfo(files = depset([headers]))]

godot_headers = rule(
    implementation = _headers_impl,
    cfg = _header_platform,
    fragments = ["apple"],
    attrs = apple_support.action_required_attrs() | {
        "archive": attr.label(mandatory = True, allow_single_file = True),
        "version": attr.string(mandatory = True),
        "header_platform": attr.label(default = Label("@apple_support//platforms:ios_arm64")),
        "_generator": attr.label(default = Label(":generate_godot_headers"), executable = True, cfg = "exec"),
        "_scons": attr.label(default = Label(":scons"), executable = True, cfg = "exec"),
        "_allowlist_function_transition": attr.label(default = "@bazel_tools//tools/allowlists/function_transition_allowlist"),
    },
)
