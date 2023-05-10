const std = @import("std");
const builtin = @import("builtin");
const Step = std.Build.Step;
const FileSource = std.Build.FileSource;
const MakeFileExecutable = @This();

pub const base_id = .custom;

step: Step,
file: FileSource,

pub fn create(
    owner: *std.Build,
    file: FileSource,
) *MakeFileExecutable {
    const self = owner.allocator.create(MakeFileExecutable) catch @panic("OOM");
    self.* = .{
        .step = Step.init(.{
            .id = base_id,
            .name = owner.fmt("make {s} executable", .{ file.getDisplayName() }),
            .owner = owner,
            .makeFn = make,
        }),
        .file = file.dupe(owner),
    };
    file.addStepDependencies(&self.step);
    return self;
}

fn make(step: *Step, prog_node: *std.Progress.Node) !void {
    _ = prog_node;

    // Only applicable for systems with Unix-style permissions
    if (builtin.os.tag == .windows)
        return;

    const self = @fieldParentPtr(MakeFileExecutable, "step", step);
    const full_path = self.file.getPath2(step.owner, step);
    const cwd = std.fs.cwd();
    const f = cwd.openFile(full_path, .{}) catch |err| {
        return step.fail("unable to make '{s}' executable: {s}", .{
            full_path, @errorName(err),
        });
    };
    const metadata = try f.metadata();
    var perms = metadata.permissions();
    for (std.meta.tags(std.fs.File.PermissionsUnix.Class)) |class| {
        if (perms.inner.unixHas(class, .read)) {
            perms.inner.unixSet(class, .{ .execute = true });
        }
    }

    // TODO Determine whether changing the file in-place breaks anything
    // important with respect to caching
    try f.setPermissions(perms);
}
