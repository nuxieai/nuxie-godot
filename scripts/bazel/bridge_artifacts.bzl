"""Expose compiled Kotlin bridge AARs with their owning consumer rules."""

load("@rules_android//providers:providers.bzl", "AndroidLibraryAarInfo")
load("@rules_apple//apple/internal/aspects:swift_dynamic_framework_aspect.bzl", "SwiftDynamicFrameworkInfo")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("@rules_swift//swift:providers.bzl", "SwiftInfo")

def _framework_module_impl(ctx):
    library = ctx.attr.deps[0]
    modules = library[SwiftInfo].direct_modules
    if len(modules) != 1 or not modules[0].swift or not modules[0].swift.generated_header:
        fail("Bridge frameworks require one owning Swift module and its Objective-C header")
    module = modules[0]
    modulemap = ctx.actions.declare_file(ctx.label.name + ".modulemap")
    ctx.actions.write(modulemap, 'framework module ' + module.name + ' {\n  header "' + module.name + '.h"\n  requires objc\n}\n')
    arch = ctx.fragments.apple.single_arch_cpu
    interface = getattr(module.swift, "swiftinterface", None)
    return [library[DefaultInfo], library[SwiftInfo], library[CcInfo], SwiftDynamicFrameworkInfo(
        module_name = module.name,
        generated_header = module.swift.generated_header,
        swiftdocs = {arch: module.swift.swiftdoc},
        swiftmodules = {arch: module.swift.swiftmodule},
        swiftinterfaces = {arch: interface} if interface else {},
        modulemap = modulemap,
    )]

# Match the pinned native SDK's fix for rules_apple 4.5 selecting a transitive C
# header instead of the bridge module's generated Swift header during bundling.
bridge_framework_module = rule(
    implementation = _framework_module_impl,
    fragments = ["apple"],
    attrs = {"deps": attr.label_list(mandatory = True, providers = [SwiftInfo, CcInfo])},
)

def _bridge_aar_impl(ctx):
    base = ctx.attr.library[AndroidLibraryAarInfo].aar
    if base == None:
        fail("The directly compiled Android bridge must provide its AAR")
    output = ctx.actions.declare_file(ctx.label.name + ".aar")
    args = ctx.actions.args()
    args.add("aar")
    args.add("--input", base)
    args.add("--output", output)
    inputs = [base]
    if ctx.file.consumer_rules:
        args.add("--consumer-rules", ctx.file.consumer_rules)
        inputs.append(ctx.file.consumer_rules)
    ctx.actions.run(
        executable = ctx.executable._tool,
        arguments = [args],
        inputs = inputs,
        outputs = [output],
        mnemonic = "NuxieBridgeAar",
    )
    return [DefaultInfo(files = depset([output]))]

bridge_aar = rule(
    implementation = _bridge_aar_impl,
    attrs = {
        "library": attr.label(mandatory = True, providers = [AndroidLibraryAarInfo]),
        "consumer_rules": attr.label(allow_single_file = True),
        "_tool": attr.label(default = Label(":bridge_artifacts"), executable = True, cfg = "exec"),
    },
)
