const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const Track = @import("Track.zig");
pub const TimedEvent = Track.TimedEvent;
pub const Event = Track.Event;

pub const Midi = @This();

format: Format,
division: Division,
tracks: []Track,

pub fn initFile(file: Io.File, io: Io, allocator: Allocator) !Midi {
    const file_length = try file.length(io);
    const buffer = try allocator.alloc(u8, file_length);
    defer allocator.free(buffer);
    var fr = file.reader(io, buffer);
    const reader = &fr.interface;
    return try readMidiFile(reader, allocator);
}

pub fn initMemory(buffer: []const u8, allocator: Allocator) !Midi {
    var reader = Io.Reader.fixed(buffer);
    return try readMidiFile(&reader, allocator);
}

pub fn deinit(self: Midi, allocator: std.mem.Allocator) void {
    for (self.tracks) |t| {
        t.deinit(allocator);
    }
    allocator.free(self.tracks);
}

// Header

pub const Header = struct {
    length: u32,
    format: Format,
    /// Number of track chunks,
    ntkrs: u16,
    division: Division

};

pub const Format = enum (u16) {
    single_track = 0,
    simultaneous_tracks = 1,
    separate_tracks = 2,
};

pub const Division = packed struct (u16) {
    const Type = enum (u1) { ticks, subdivisions};

    format: Type,
    value: u15,
};

pub const Key = enum (u8) {
    c0 = 0, cs0, d0, ds0, e0, f0, fs0, g0, gs0, a0, as0, b0,
    c1, cs1, d1, ds1, e1, f1, fs1, g1, gs1, a1, as1, b1,
    c2, cs2, d2, ds2, e2, f2, fs2, g2, gs2, a2, as2, b2,
    c3, cs3, d3, ds3, e3, f3, fs3, g3, gs3, a3, as3, b3,
    c4, cs4, d4, ds4, e4, f4, fs4, g4, gs4, a4, as4, b4,
    c5, cs5, d5, ds5, e5, f5, fs5, g5, gs5, a5, as5, b5,
    c6, cs6, d6, ds6, e6, f6, fs6, g6, gs6, a6, as6, b6,
    c7, cs7, d7, ds7, e7, f7, fs7, g7, gs7, a7, as7, b7,
    c8, cs8, d8, ds8, e8, f8, fs8, g8, gs8, a8, as8, b8,
    c9, cs9, d9, ds9, e9, f9, fs9, g9, gs9, a9, as9, b9,
    c10, cs10, d10, ds10, e10, f10, fs10, g10,
};

// Low level reading functions

fn readMidiFile(reader: *Io.Reader, allocator: Allocator) !Midi {
    std.debug.assert(reader.seek == 0);
    const header = try readHeaderChunk(reader);
    const tracks = try allocator.alloc(Track, header.ntkrs);
    for (0..header.ntkrs) |i| {
        tracks[i] = try readTrackChunk(reader, allocator);
    }
    return .{
        .format = header.format,
        .division = header.division,
        .tracks = tracks
    };
}

fn readHeaderChunk(reader: *Io.Reader) !Header {
    const title = try reader.take(4);
    // if (!std.mem.eql(u8, try reader.take(4), "MThd")) return error.WrongFileType;
    std.debug.assert(std.mem.eql(u8, title, "MThd"));
    return Header{
        .length = try reader.takeInt(u32, .big),
        .format = try reader.takeEnum(Format, .big),
        .ntkrs = try reader.takeInt(u16, .big),
        .division = @bitCast(try reader.takeInt(u16, .big)),
    };
}

fn readTrackChunk(reader: *Io.Reader, allocator: std.mem.Allocator) !Track {
    const title = try reader.take(4);
    std.debug.assert(std.mem.eql(u8, title, "MTrk"));
    const byte_count = try reader.takeInt(u32, .big);
    var events: std.ArrayList(TimedEvent) = try .initCapacity(allocator, 100);

    var running_status: ?u8 = null;
    const end = reader.seek + byte_count;
    while (reader.seek < end) {
        const delta = try readVariableLengthInt(u28, reader);
        const event = try readEvent(reader, &running_status, allocator);
        try events.append(
            allocator,
            .{
                .delta = .{ .ticks = delta },
                .event = event
            }
        );

        if (event == .meta and @intFromEnum(event.meta.type) == 0x2F) break;
    }
    return .{ .events = try events.toOwnedSlice(allocator) };

}

fn readEvent(reader: *Io.Reader, running_status: *?u8, allocator: std.mem.Allocator) !Event {
    var status = try reader.takeInt(u8, .big);

    if (status & 0b10000000 == 0) status = running_status.* orelse unreachable;
    // Meta event always preceded by 0xFF
    if (status == 0xFF) {
        running_status.* = null;
        const event_type = try reader.takeInt(u8, .big);
        const data_len = try readVariableLengthInt(u28, reader);
        const data = try reader.take(data_len);
        return .{ .meta = .{
            .type = @enumFromInt(event_type),
            .data = try allocator.dupe(u8, data)}
        };
    }

    if (status == 0b11110000 or status == 0b11110111) {
        running_status.* = null;
        const data_len = try readVariableLengthInt(u28, reader);
        const data = try reader.take(data_len);
        return .{ .sysex = try allocator.dupe(u8, data) };
    }

    // Channel Message
    running_status.* = status;
    const message_type: u4 = @intCast(status >> 4);
    const channel: u4 = @intCast(status & 0b00001111);
    const data_len: u8 = switch (message_type) {
        0xC, 0xD => 1,
        else => 2
    };
    var data: [2]u8 = .{ 0, 0 };
    data[0] = try reader.takeInt(u8, .big);
    if (data_len == 2) data[1] = try reader.takeInt(u8, .big);

    return .{ .midi = .{
        .channel = channel,
        .type = @enumFromInt(message_type),
        .data_len = data_len,
        .data = data
    }};
}

fn readVariableLengthInt(T: type, reader: *Io.Reader) !T {
    var value: T = 0;
    switch (@typeInfo(T)) {
        .int => |i| {
            std.debug.assert(i.signedness == .unsigned);
            std.debug.assert(i.bits <= 28);
            for (0..4) |_| {
                const byte = (try reader.take(1))[0];
                value = (value << 7) | (byte & 0b01111111);
                if (byte & 0b10000000 == 0) return value;
            }
            unreachable;
        },
        else => unreachable
    }
}

test "declarations" { std.testing.refAllDecls(Midi); }

test initFile {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const cwd = Io.Dir.cwd();
    const file = try cwd.openFile(io, "lib/Billie-Jean.mid", .{});

    const midi = try Midi.initFile(file, io, allocator);
    defer midi.deinit(allocator);
}

test initMemory {
    const allocator = std.testing.allocator;

    const memory = @embedFile("Billie-Jean.mid");
    const midi = try Midi.initMemory(memory, allocator);
    defer midi.deinit(allocator);
}
