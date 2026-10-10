"""Verified imports of the native SDK producers' sdk-artifacts.json products."""

def _native_repository_impl(ctx):
    pins = json.decode(ctx.read(ctx.attr.pins))
    revision = pins[ctx.attr.sdk]["revision"]
    selected = ctx.attr.manifest or ctx.getenv("NUXIE_" + ctx.attr.sdk.upper() + "_ARTIFACTS", "")
    if not selected or not selected.startswith("/"):
        fail("Set NUXIE_" + ctx.attr.sdk.upper() + "_ARTIFACTS to the absolute prepared sdk-artifacts.json path or its directory")
    manifest = ctx.path(selected)
    if manifest.is_dir:
        manifest = manifest.get_child("sdk-artifacts.json")
    if not manifest.exists:
        fail("Native SDK artifacts are missing: " + str(manifest))
    ctx.watch_tree(manifest.dirname)
    ctx.read(manifest, watch = "yes")
    python = ctx.which("python3")
    if python == None:
        fail("python3 is required to verify prepared native artifacts")
    command = [python, ctx.path(ctx.attr.verifier), manifest, "--sdk", ctx.attr.sdk, "--expected-revision", revision]
    for label, coordinate in ctx.attr.android_dependencies.items():
        command.extend(["--android-dependency", coordinate + "=" + str(label)])
    result = ctx.execute(command)
    if result.return_code:
        fail("Native SDK artifact verification failed:\n" + result.stderr)
    plan = json.decode(result.stdout)
    # Expose only receipt-verified files. In particular, an Android producer may
    # preserve unrelated Maven versions beside the selected version.
    for path in plan["files"]:
        ctx.symlink(manifest.dirname.get_child(path), "artifacts/" + path)
    for path in plan["symlinks"]:
        ctx.symlink(manifest.dirname.get_child(path), "artifacts/" + path)
    ctx.symlink(manifest, "sdk-artifacts.json")
    ctx.file("BUILD.bazel", plan["build"])

_native_repository = repository_rule(
    implementation = _native_repository_impl,
    attrs = {
        "sdk": attr.string(mandatory = True, values = ["ios", "android"]),
        "pins": attr.label(allow_single_file = True, mandatory = True),
        "manifest": attr.string(),
        "android_dependencies": attr.label_keyed_string_dict(),
        "verifier": attr.label(default = Label(":native_artifacts.py"), allow_single_file = True),
    },
    environ = ["NUXIE_IOS_ARTIFACTS", "NUXIE_ANDROID_ARTIFACTS"],
    local = True,
)

def _extension_impl(ctx):
    tags = [tag for module in ctx.modules for tag in module.tags.artifacts]
    if len(tags) != 1:
        fail("Select exactly one downstream NATIVE-PINS.json native artifact contract")
    tag = tags[0]
    _native_repository(name = "nuxie_native_ios", sdk = "ios", pins = tag.pins, manifest = tag.ios_manifest)
    _native_repository(name = "nuxie_native_android", sdk = "android", pins = tag.pins, manifest = tag.android_manifest, android_dependencies = tag.android_dependencies)

native_artifacts = module_extension(
    implementation = _extension_impl,
    tag_classes = {"artifacts": tag_class(attrs = {
        "pins": attr.label(allow_single_file = True, mandatory = True),
        "ios_manifest": attr.string(),
        "android_manifest": attr.string(),
        # Keys are configured Maven labels; values are exact producer POM
        # coordinates, including versions. Missing edges fail before compiling.
        "android_dependencies": attr.label_keyed_string_dict(),
    })},
)
