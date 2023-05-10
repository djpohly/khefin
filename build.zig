const std = @import("std");
const alloc = std.heap.page_allocator;

const mans = std.ComptimeStringMap([]const u8, .{
    .{"man/1/khefin-ssh-askpass.m4", "share/man/man1/khefin-ssh-askpass.1.gz"},
    .{"man/1/khefin.m4", "share/man/man1/khefin.1.gz"},
    .{"man/8/khefin-add-luks-key.m4", "share/man/man8/khefin-add-luks-key.8.gz"},
    .{"man/8/khefin-cryptsetup-keyscript.m4", "share/man/man8/khefin-cryptsetup-keyscript.8.gz"},
});

const m4s = std.ComptimeStringMap([]const u8, .{
    .{"scripts/bash-completion.m4", "share/bash-completion/completions/" ++ app_name},
    .{"scripts/add-luks-key.m4", "bin/" ++ app_name ++ "-add-luks-key"},
    .{"scripts/mkinitcpio/install.m4", "lib/initcpio/install/" ++ app_name},
    .{"scripts/mkinitcpio/run.m4", "lib/initcpio/hooks/" ++ app_name},
    .{"scripts/initramfs-tools/hook.m4", "etc/initramfs-tools/hooks/crypt" ++ app_name},
    .{"scripts/initramfs-tools/keyscript.m4", "lib/" ++ app_name ++ "/cryptsetup-keyscript"},
    .{"scripts/ssh-askpass.m4", "bin/" ++ app_name ++ "-ssh-askpass"},
});

// Note: localize?
const month_name = [_][]const u8{
    "",
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
};

// Version will be retrieved from the metadata file
const metadata = KeyValueFileStruct("metadata.make"){};

/// Parses a key-value file and returns a struct type containing a field for
/// each key and default values given by the file.
fn KeyValueFileStruct(comptime filename: []const u8) type {
    var keys: []const []const u8 = &[_][]const u8{};
    var values: []const []const u8 = &[_][]const u8{};

    // Read lines from the given file.  Each line is formatted "key=value".
    {
        const kvdata = @embedFile(filename);
        var lines = std.mem.split(u8, kvdata, "\n");

        // Build parallel arrays of keys and values
        while (lines.next()) |line| {
            // Ignore lines with no equals sign
            const eq_idx = std.mem.indexOfScalar(u8, line, '=') orelse continue;

            keys = keys ++ .{ line[0..eq_idx] };
            values = values ++ .{ line[eq_idx + 1 ..] };
        }
    }

    // Construct the array of struct fields
    var fields: [keys.len]std.builtin.Type.StructField = undefined;
    for (&fields, keys, values) |*field, key, value| {
        field.* = std.builtin.Type.StructField{
            .name = key,
            .type = [:0]const u8,
            .default_value = @ptrCast(*const anyopaque, &value),
            .alignment = 0,
            .is_comptime = false,
        };
    }

    // Return a corresponding type
    return @Type(std.builtin.Type{
        .Struct = std.builtin.Type.Struct{
            .layout = .Auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

// Version will be retrieved from the package/info file
const app_name = metadata.APPNAME;
const app_version = metadata.APPVERSION;
const longest_valid_passphrase = "1024";
const warn_on_memory_lock_errors = "true";

const c_sources = .{
    "src/authenticator.c",
    "src/cryptography.c",
    "src/enrol.c",
    "src/enumerate.c",
    "src/files.c",
    "src/generate.c",
    "src/help.c",
    "src/invocation.c",
    "src/main.c",
    "src/memory.c",
    "src/serialization.c",
    "src/serialization/v1.c",
};

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "khefin",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .target = target,
        .optimize = optimize,
    });

    exe.addCSourceFiles(&c_sources, &.{});

    exe.addIncludePath("include");
    exe.defineCMacro("APPNAME", "\"" ++ app_name ++ "\"");
    exe.defineCMacro("APPVERSION", "\"" ++ app_version ++ "-zig\"");
    exe.defineCMacro("LONGEST_VALID_PASSPHRASE", longest_valid_passphrase);
    exe.defineCMacro("WARN_ON_MEMORY_LOCK_ERRORS", warn_on_memory_lock_errors);

    exe.linkSystemLibrary("fido2");
    exe.linkSystemLibrary("cbor");
    exe.linkSystemLibrary("sodium");
    exe.linkLibC();

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // Get the current date for header
    const esecs = std.time.epoch.EpochSeconds{ .secs = @intCast(u64, std.time.timestamp()) };
    const year_day = esecs.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const app_date_arg = try std.fmt.allocPrint(alloc, "-Dm4_APPDATE={} {s} {}", .{month_day.day_index, month_name[month_day.month.numeric()], year_day.year});
    defer alloc.destroy(app_date_arg);

    // Set up variables arg
    const vars_absolute = try std.fs.realpathAlloc(alloc, "./variables.m4");
    defer alloc.destroy(vars_absolute);

    // Set up install-prefix arg
    const install_prefix_arg = try std.fmt.allocPrint(alloc,
            "-Dm4_INSTALL_PREFIX={s}", .{b.install_prefix});
    defer alloc.destroy(install_prefix_arg);

    const m4_cmd = .{
        "m4",
        "-Dm4_APPNAME=" ++ app_name,
        "-Dm4_APPVERSION=" ++ app_version,
        app_date_arg,
        "-Dm4_WARN_ON_MEMORY_LOCK_ERRORS=" ++ warn_on_memory_lock_errors,
        install_prefix_arg,
        "--prefix-builtins",
        vars_absolute,
    };

    for (m4s.kvs) |kv| {
        const src_absolute = try std.fs.realpathAlloc(alloc, kv.key);
        defer alloc.destroy(src_absolute);

        const m4_step = b.addSystemCommand(&m4_cmd);
        m4_step.addArg(src_absolute);

        b.getInstallStep().dependOn(&b.addInstallFile(m4_step.captureStdOut(), kv.value).step);
    }

    // Manual pages
    const man_step = b.step("manpages", "Build and install manual pages");
    b.getInstallStep().dependOn(man_step);

    for (mans.kvs) |kv| {
        const src_absolute = try std.fs.realpathAlloc(alloc, kv.key);
        defer alloc.destroy(src_absolute);

        const m4_step = b.addSystemCommand(&m4_cmd);
        m4_step.addArg(src_absolute);

        var gz_step = b.addSystemCommand(&.{
            "gzip",
            "-c",
        });
        gz_step.addFileSourceArg(m4_step.captureStdOut());

        man_step.dependOn(&b.addInstallFile(gz_step.captureStdOut(), kv.value).step);
    }
}
