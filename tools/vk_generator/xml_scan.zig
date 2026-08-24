const std = @import("std");

pub const Command = struct {
    /// Original C function name, e.g. "vkCreateInstance". Slices into the source xml buffer.
    c_name: []const u8,
    /// Ordered parameter names, e.g. ["pCreateInfo", "pAllocator", "pInstance"]. Slice into the source xml buffer.
    params: []const []const u8,
};

/// Slices out the text between the first `<tag_prefix ...>` (or self-closing form is not expected here)
/// and the matching `</close_tag>`, exclusive of both delimiters.
pub fn extractBlock(xml: []const u8, open_tag_prefix: []const u8, close_tag: []const u8) []const u8 {
    const open_start = std.mem.indexOf(u8, xml, open_tag_prefix) orelse @panic("vk.xml: open tag not found");
    const tag_end = std.mem.indexOfPos(u8, xml, open_start, ">") orelse @panic("vk.xml: malformed open tag");
    const close_start = std.mem.indexOfPos(u8, xml, tag_end, close_tag) orelse @panic("vk.xml: close tag not found");
    return xml[tag_end + 1 .. close_start];
}

fn sliceBetween(haystack: []const u8, open: []const u8, close: []const u8) ?[]const u8 {
    const start = std.mem.indexOf(u8, haystack, open) orelse return null;
    const content_start = start + open.len;
    const end = std.mem.indexOfPos(u8, haystack, content_start, close) orelse return null;
    return haystack[content_start..end];
}

fn attrValue(tag_attrs: []const u8, name: []const u8) ?[]const u8 {
    var buf: [64]u8 = undefined;
    const needle = std.fmt.bufPrint(&buf, "{s}=\"", .{name}) catch return null;
    const start = std.mem.indexOf(u8, tag_attrs, needle) orelse return null;
    const value_start = start + needle.len;
    const end = std.mem.indexOfPos(u8, tag_attrs, value_start, "\"") orelse return null;
    return tag_attrs[value_start..end];
}

/// vk.xml gates commands/params to a specific API surface via `api="vulkan"` or
/// `api="vulkan,vulkansc"` (comma-separated). Absence of the attribute means "all APIs".
/// This project only wants the "vulkan" API, never the "vulkansc" (safety-critical) variants.
fn apiIncludesVulkan(api: ?[]const u8) bool {
    const value = api orelse return true;
    var it = std.mem.splitScalar(u8, value, ',');
    while (it.next()) |token| {
        if (std.mem.eql(u8, token, "vulkan")) return true;
    }
    return false;
}

/// Iterates `<command>` elements within an already-extracted `<commands>...</commands>` block,
/// yielding only full (non-alias) definitions whose return type is VkResult and whose `api`
/// attribute (if any) includes "vulkan".
pub const CommandIterator = struct {
    xml: []const u8,
    pos: usize = 0,

    pub fn next(self: *CommandIterator, allocator: std.mem.Allocator) !?Command {
        while (true) {
            const cmd_start = std.mem.indexOfPos(u8, self.xml, self.pos, "<command") orelse return null;
            const tag_end = std.mem.indexOfPos(u8, self.xml, cmd_start, ">") orelse return null;

            const attrs_raw = self.xml[cmd_start + "<command".len .. tag_end];
            const attrs_trimmed = std.mem.trimEnd(u8, attrs_raw, " \t\r\n");
            const self_closing = attrs_trimmed.len > 0 and attrs_trimmed[attrs_trimmed.len - 1] == '/';
            const attrs = if (self_closing) attrs_trimmed[0 .. attrs_trimmed.len - 1] else attrs_raw;

            if (self_closing) {
                // Pure alias command (`<command name="X" alias="Y"/>`): the aliased target
                // is already covered under its own name, so skip it.
                self.pos = tag_end + 1;
                continue;
            }

            const body_end = std.mem.indexOfPos(u8, self.xml, tag_end + 1, "</command>") orelse return null;
            const body = self.xml[tag_end + 1 .. body_end];
            self.pos = body_end + "</command>".len;

            if (!apiIncludesVulkan(attrValue(attrs, "api"))) continue;

            const proto = sliceBetween(body, "<proto>", "</proto>") orelse continue;
            // void-returning commands have no <type> element in their <proto> (just the bare
            // word "void"), so this also naturally filters them out along with non-VkResult types.
            const return_type = sliceBetween(proto, "<type>", "</type>") orelse continue;
            if (!std.mem.eql(u8, return_type, "VkResult")) continue;

            const c_name = sliceBetween(proto, "<name>", "</name>") orelse continue;

            // <implicitexternsyncparams> is a trailing documentation block containing prose
            // wrapped in its own <param> tags; truncate before it so it's never mistaken for
            // a real parameter.
            const scan_body = if (std.mem.indexOf(u8, body, "<implicitexternsyncparams>")) |idx|
                body[0..idx]
            else
                body;

            var params: std.ArrayList([]const u8) = .empty;
            var ppos: usize = 0;
            while (std.mem.indexOfPos(u8, scan_body, ppos, "<param")) |p_start| {
                const p_tag_end = std.mem.indexOfPos(u8, scan_body, p_start, ">") orelse break;
                const p_attrs = scan_body[p_start + "<param".len .. p_tag_end];
                const p_body_end = std.mem.indexOfPos(u8, scan_body, p_tag_end + 1, "</param>") orelse break;
                const p_body = scan_body[p_tag_end + 1 .. p_body_end];
                ppos = p_body_end + "</param>".len;

                if (!apiIncludesVulkan(attrValue(p_attrs, "api"))) continue;

                const p_name = sliceBetween(p_body, "<name>", "</name>") orelse continue;
                try params.append(allocator, p_name);
            }

            return Command{ .c_name = c_name, .params = try params.toOwnedSlice(allocator) };
        }
    }
};

/// "vkCreateInstance" -> "createInstance": strip the leading "vk", lowercase only the new
/// first character, keep the rest (including any trailing KHR/EXT suffix) verbatim.
pub fn zigName(buf: []u8, c_name: []const u8) []const u8 {
    std.debug.assert(std.mem.startsWith(u8, c_name, "vk"));
    const rest = c_name[2..];
    std.debug.assert(rest.len <= buf.len);
    @memcpy(buf[0..rest.len], rest);
    buf[0] = std.ascii.toLower(buf[0]);
    return buf[0..rest.len];
}

test "skips alias commands" {
    const xml =
        \\<commands>
        \\<command name="vkFoo" alias="vkBar"/>
        \\<command><proto><type>VkResult</type> <name>vkBar</name></proto><param><type>int</type> <name>x</name></param></command>
        \\</commands>
    ;
    const block = extractBlock(xml, "<commands", "</commands>");
    var it = CommandIterator{ .xml = block };
    const first = (try it.next(std.testing.allocator)).?;
    defer std.testing.allocator.free(first.params);
    try std.testing.expectEqualStrings("vkBar", first.c_name);
    try std.testing.expectEqual(@as(?Command, null), try it.next(std.testing.allocator));
}

test "drops vulkansc-only command duplicates" {
    const xml =
        \\<commands>
        \\<command api="vulkansc"><proto><type>VkResult</type> <name>vkCreateDevice</name></proto></command>
        \\<command api="vulkan"><proto><type>VkResult</type> <name>vkCreateDevice</name></proto><param><type>int</type> <name>x</name></param></command>
        \\</commands>
    ;
    const block = extractBlock(xml, "<commands", "</commands>");
    var it = CommandIterator{ .xml = block };
    const first = (try it.next(std.testing.allocator)).?;
    defer std.testing.allocator.free(first.params);
    try std.testing.expectEqualStrings("vkCreateDevice", first.c_name);
    try std.testing.expectEqual(@as(usize, 1), first.params.len);
    try std.testing.expectEqual(@as(?Command, null), try it.next(std.testing.allocator));
}

test "drops vulkansc-only param duplicates within a command" {
    const xml =
        \\<commands>
        \\<command><proto><type>VkResult</type> <name>vkCreateSwapchainKHR</name></proto>
        \\<param api="vulkansc"><type>int</type> <name>pCreateInfo</name></param>
        \\<param api="vulkan"><type>int</type> <name>pCreateInfo</name></param>
        \\</command>
        \\</commands>
    ;
    const block = extractBlock(xml, "<commands", "</commands>");
    var it = CommandIterator{ .xml = block };
    const cmd = (try it.next(std.testing.allocator)).?;
    defer std.testing.allocator.free(cmd.params);
    try std.testing.expectEqual(@as(usize, 1), cmd.params.len);
    try std.testing.expectEqualStrings("pCreateInfo", cmd.params[0]);
}

test "ignores implicitexternsyncparams prose" {
    const xml =
        \\<commands>
        \\<command><proto><type>VkResult</type> <name>vkDeviceWaitIdle</name></proto>
        \\<param><type>int</type> <name>device</name></param>
        \\<implicitexternsyncparams><param>all queues</param></implicitexternsyncparams>
        \\</command>
        \\</commands>
    ;
    const block = extractBlock(xml, "<commands", "</commands>");
    var it = CommandIterator{ .xml = block };
    const cmd = (try it.next(std.testing.allocator)).?;
    defer std.testing.allocator.free(cmd.params);
    try std.testing.expectEqual(@as(usize, 1), cmd.params.len);
    try std.testing.expectEqualStrings("device", cmd.params[0]);
}

test "skips void-returning commands" {
    const xml =
        \\<commands>
        \\<command><proto>void <name>vkDestroyInstance</name></proto><param><type>int</type> <name>instance</name></param></command>
        \\</commands>
    ;
    const block = extractBlock(xml, "<commands", "</commands>");
    var it = CommandIterator{ .xml = block };
    try std.testing.expectEqual(@as(?Command, null), try it.next(std.testing.allocator));
}

test "zigName strips leading vk and lowercases only the first letter" {
    var buf: [128]u8 = undefined;
    try std.testing.expectEqualStrings("createInstance", zigName(&buf, "vkCreateInstance"));
    try std.testing.expectEqualStrings("getPhysicalDeviceSurfaceFormatsKHR", zigName(&buf, "vkGetPhysicalDeviceSurfaceFormatsKHR"));
}
