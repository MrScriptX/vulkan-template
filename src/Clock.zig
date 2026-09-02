const Self = @This();

const std = @import("std");

io: std.Io,
last_ns: std.Io.Timestamp,

pub fn init(io: std.Io) Self {
    return .{
        .io = io,
        .last_ns = std.Io.Clock.now(.awake, io)
    };
}

pub fn s_delta_time(self: *Self) i64 {
    const elapsed = self.last_ns.untilNow(self.io, .awake);
    self.last_ns = std.Io.Clock.now(.awake, self.io);

    return elapsed.toSeconds();
}

pub fn ms_delta_time(self: *Self) i64 {
    const elapsed = self.last_ns.untilNow(self.io, .awake);
    self.last_ns = std.Io.Clock.now(.awake, self.io);
    
    return elapsed.toMilliseconds();
}

pub fn ns_delta_time(self: *Self) i96 {
    const elapsed = self.last_ns.untilNow(self.io, .awake);
    self.last_ns = std.Io.Clock.now(.awake, self.io);
    
    return elapsed.toNanoseconds();
}
