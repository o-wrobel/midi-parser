const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

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

pub fn deinit(self: Midi, allocator: std.mem.Allocator) void {
    for (self.tracks) |t| {
        t.deinit(allocator);
    }
    allocator.free(self.tracks);
}

pub const Track = struct {
    events: []MtrkEvent,

    pub fn deinit(self: Track, allocator: std.mem.Allocator) void {
        for (self.events) |e| {
            switch (e.event) {
                .sysex => |s| { allocator.free(s); },
                .meta => |m| { allocator.free(m.data); },
                else => {}
            }
        }
        allocator.free(self.events);
    }
};

pub const MtrkEvent = struct {
    delta: u28, // Stored in file as a variable length value
    event: Event
};
pub const Event = union (enum) {
    pub const MidiMessage = struct {
        type: u4,
        channel: u4,
        data_len: u8,
        data: [2]u8
    };
    pub const Meta = struct {
        type: u8,
        data: []u8
    };
    midi: MidiMessage,
    sysex: []u8,
    meta: Meta
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
pub const Header = struct {
    length: u32,
    format: Format,
    /// Number of track chunks,
    ntkrs: u16,
    division: Division

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
    var events: std.ArrayList(MtrkEvent) = try .initCapacity(allocator, 100);

    var running_status: ?u8 = null;
    const end = reader.seek + byte_count;
    while (reader.seek < end) {
        const delta = try readVariableLengthInt(u28, reader);
        const event = try readEvent(reader, &running_status, allocator);
        try events.append(
            allocator,
            .{
                .delta = delta,
                .event = event
            }
        );

        if (event == .meta and event.meta.type == 0x2F) break;
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
            .type = event_type,
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
        .type = message_type,
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
    const file = try cwd.openFile(io, "Billie-Jean.mid", .{});

    const midi = try Midi.initFile(file, io, allocator);
    defer midi.deinit(allocator);
}
