const std = @import("std");
const log = std.log.scoped(.archive);
const macho = std.macho;
const mem = std.mem;

pub fn decodeArch(cputype: macho.cpu_type_t, comptime logError: bool) !std.Target.Cpu.Arch {
    const cpu_arch: std.Target.Cpu.Arch = switch (cputype) {
        macho.CPU_TYPE_ARM64 => .aarch64,
        macho.CPU_TYPE_X86_64 => .x86_64,
        else => {
            if (logError) {
                log.err("unsupported cpu architecture 0x{x}", .{cputype});
            }
            return error.UnsupportedCpuArchitecture;
        },
    };
    return cpu_arch;
}

pub fn getLibraryOffset(reader: anytype, cpu_arch: std.Target.Cpu.Arch) !u64 {
    const fat_header = try reader.readStructBig(macho.fat_header);
    if (fat_header.magic != macho.FAT_MAGIC) return 0;

    var fat_arch_index: u32 = 0;
    while (fat_arch_index < fat_header.nfat_arch) : (fat_arch_index += 1) {
        const fat_arch = try reader.readStructBig(macho.fat_arch);
        // If we come across an architecture that we do not know how to handle, that's
        // fine because we can keep looking for one that might match.
        const lib_arch = decodeArch(fat_arch.cputype, false) catch |err| switch (err) {
            error.UnsupportedCpuArchitecture => continue,
        };
        if (lib_arch == cpu_arch) {
            // We have found a matching architecture!
            return fat_arch.offset;
        }
    } else {
        log.err("Could not find matching cpu architecture in fat library: expected {s}", .{
            @tagName(cpu_arch),
        });
        return error.MismatchedCpuArchitecture;
    }
}
