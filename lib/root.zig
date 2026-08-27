const std = @import("std");
const Io = std.Io;
const log = std.log.info;

const Midi = @import("Midi.zig");
const Header = Midi.Header;
const Track = Midi.Track;
const Event = Midi.Event;
const Format = Midi.Format;
const MtrkEvent = Midi.MtrkEvent;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const cwd = Io.Dir.cwd();
    const file = try cwd.openFile(io, "Billie-Jean.mid", .{});

    const midi = try Midi.initFile(file, io, gpa);
    defer midi.deinit(gpa);
    std.debug.print("{any}", .{midi});

}
