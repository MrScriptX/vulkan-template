const std = @import("std");
const model = @import("model.zig");

// ---------------------------------------------------------------------------
// Low-level substring-scanning helpers (same hand-rolled style as the
// original xml_scan.zig — vk.xml is regular enough that a real XML
// tokenizer/DOM isn't needed).
// ---------------------------------------------------------------------------

/// Slices out the text between the first `<tag_prefix ...>` and the matching
/// `</close_tag>`, exclusive of both delimiters.
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

/// vk.xml gates types/commands/params to a specific API surface via
/// `api="vulkan"` or `api="vulkan,vulkansc"`. Absence means "all APIs". This
/// project only wants "vulkan", never "vulkansc" (safety-critical) variants.
fn apiIncludesVulkan(api: ?[]const u8) bool {
    const value = api orelse return true;
    var it = std.mem.splitScalar(u8, value, ',');
    while (it.next()) |token| {
        if (std.mem.eql(u8, token, "vulkan")) return true;
    }
    return false;
}

/// A generic self-closing-or-not tag cursor: given `xml` and a byte offset
/// just after `<tag_name`, returns the attribute text and whether the tag is
/// self-closing (`.../>`), positioned so the caller can find the body (if
/// any) starting right after the returned `tag_end`.
const TagHeader = struct {
    attrs: []const u8,
    self_closing: bool,
    tag_end: usize, // index of the '>' character
};

/// Finds the matching `</close_tag>` for a body that may contain nested
/// occurrences of the SAME tag name -- e.g. `<type category="handle">`
/// bodies nest an inner `<type>VK_DEFINE_HANDLE</type>` element, and
/// `<type category="struct">` bodies nest one `<type>FieldType</type>` per
/// `<member>`. A plain `indexOf(xml, "</type>")` would stop at the first
/// nested occurrence instead of the real end of the outer element.
fn findMatchingClose(xml: []const u8, body_start: usize, open_prefix: []const u8, close_tag: []const u8) ?usize {
    var depth: usize = 1;
    var pos = body_start;
    while (true) {
        const next_open = std.mem.indexOfPos(u8, xml, pos, open_prefix);
        const next_close = std.mem.indexOfPos(u8, xml, pos, close_tag) orelse return null;
        if (next_open != null and next_open.? < next_close) {
            const tag_end = std.mem.indexOfPos(u8, xml, next_open.?, ">") orelse return null;
            const self_closing = tag_end > 0 and xml[tag_end - 1] == '/';
            if (!self_closing) depth += 1;
            pos = tag_end + 1;
            continue;
        }
        depth -= 1;
        if (depth == 0) return next_close;
        pos = next_close + close_tag.len;
    }
}

fn scanTagHeader(xml: []const u8, after_name: usize) ?TagHeader {
    const tag_end = std.mem.indexOfPos(u8, xml, after_name, ">") orelse return null;
    const raw = xml[after_name..tag_end];
    const trimmed = std.mem.trimEnd(u8, raw, " \t\r\n");
    const self_closing = trimmed.len > 0 and trimmed[trimmed.len - 1] == '/';
    const attrs = if (self_closing) trimmed[0 .. trimmed.len - 1] else raw;
    return .{ .attrs = attrs, .self_closing = self_closing, .tag_end = tag_end };
}

/// Parses a decimal (optionally negative) integer, ignoring a trailing
/// unsigned/long-long C literal suffix (`U`, `UL`, `ULL`, `L`, `LL`, `F`).
/// Also understands the handful of `(~0U)`-style bitwise-not sentinels used
/// by vk.xml's "API Constants" block. Returns null (rather than erroring) for
/// anything else (float literals, quoted strings) so callers can skip them.
fn parseCLiteralInt(raw: []const u8) ?i64 {
    var text = std.mem.trim(u8, raw, " \t");
    if (std.mem.startsWith(u8, text, "(~") and std.mem.endsWith(u8, text, ")")) {
        const inner = text[2 .. text.len - 1];
        var digits_end: usize = 0;
        while (digits_end < inner.len and std.ascii.isDigit(inner[digits_end])) digits_end += 1;
        const base = std.fmt.parseInt(u64, inner[0..digits_end], 10) catch return null;
        const is64 = std.mem.indexOfScalar(u8, inner[digits_end..], 'L') != null;
        const max: u64 = if (is64) std.math.maxInt(u64) else std.math.maxInt(u32);
        return @bitCast(max -% base);
    }
    var negative = false;
    if (text.len > 0 and text[0] == '-') {
        negative = true;
        text = text[1..];
    }
    var digits_end: usize = 0;
    while (digits_end < text.len and std.ascii.isDigit(text[digits_end])) digits_end += 1;
    if (digits_end == 0) return null;
    if (digits_end < text.len and text[digits_end] == '.') return null; // float literal, e.g. "1000.0F"
    const magnitude = std.fmt.parseInt(i64, text[0..digits_end], 10) catch return null;
    return if (negative) -magnitude else magnitude;
}

// ---------------------------------------------------------------------------
// Member / parameter type-slot parsing, shared by struct/union members and
// command parameters. vk.xml renders these as:
//   <member optional="true">const <type>char</type>* const*  <name>foo</name>[4]</member>
// ---------------------------------------------------------------------------

fn parseTypeSlot(body: []const u8, attrs: []const u8) ?model.Member {
    const name = sliceBetween(body, "<name>", "</name>") orelse return null;
    const base = sliceBetween(body, "<type>", "</type>") orelse {
        // A few members have no <type> at all (e.g. plain `void* pUserData`
        // handled elsewhere) -- treat "void" textual members defensively.
        return null;
    };

    const before_type = body[0 .. std.mem.indexOf(u8, body, "<type>").?];
    const type_close = std.mem.indexOf(u8, body, "</type>").? + "</type>".len;
    const name_start = std.mem.indexOf(u8, body, "<name>").?;
    const between = body[type_close..name_start];
    const after_name_start = name_start + "<name>".len + name.len + "</name>".len;
    const after_name = if (after_name_start <= body.len) body[after_name_start..] else "";

    var pointer_depth: u2 = 0;
    for (between) |ch| {
        if (ch == '*') pointer_depth +|= 1;
    }
    const is_const = std.mem.indexOf(u8, before_type, "const") != null or
        std.mem.indexOf(u8, between, "const") != null;

    // A `[` immediately following `</name>` is a real fixed-size array
    // marker (`[4]` or `[<enum>VK_UUID_SIZE</enum>]`). A `[` occurring
    // later in `after_name` is just prose inside a trailing `<comment>`
    // element (Vulkan doc comments routinely use bracket notation for
    // ranges) and must NOT be mistaken for an array length.
    var array_len: ?[]const u8 = null;
    if (after_name.len > 0 and after_name[0] == '[') {
        const br_start: usize = 0;
        if (std.mem.indexOfScalarPos(u8, after_name, br_start, ']')) |br_end| {
            var inner = after_name[br_start + 1 .. br_end];
            // May be a literal ("4") or wrapped in an <enum>NAME</enum> reference.
            if (sliceBetween(inner, "<enum>", "</enum>")) |sym| {
                inner = sym;
            }
            array_len = std.mem.trim(u8, inner, " \t");
        }
    }

    return .{
        .name = name,
        .type = .{
            .base = base,
            .pointer_depth = pointer_depth,
            .is_const = is_const,
            .is_optional = attrValue(attrs, "optional") != null,
            .array_len = array_len,
        },
    };
}

// ---------------------------------------------------------------------------
// `<enums>` value-list builder: used both for the base `<enums name="X">`
// blocks and for extension/feature-contributed values, so both paths can
// merge into the same growable list before the registry is finalized.
// ---------------------------------------------------------------------------

const EnumBuilder = struct {
    name: []const u8,
    is_bitmask: bool,
    bit_width: u8,
    values: std.ArrayList(model.EnumValue) = .empty,
    seen: std.StringHashMapUnmanaged(void) = .empty,

    fn addValue(self: *EnumBuilder, gpa: std.mem.Allocator, name: []const u8, value: i64) !void {
        if (self.seen.contains(name)) return;
        try self.seen.put(gpa, name, {});
        try self.values.append(gpa, .{ .name = name, .value = value });
    }
};

const Registry_ = struct {
    gpa: std.mem.Allocator,
    /// FlagBits enum name -> its Flags typedef name, e.g.
    /// "VkImageUsageFlagBits" -> "VkImageUsageFlags". Bitmask value blocks
    /// and extension-contributed bitmask values are always keyed by the
    /// FlagBits name in vk.xml, but struct/command members reference the
    /// Flags typedef -- so the EnumType itself is stored under the Flags
    /// name, and this map lets both `<enums>` blocks and extension/feature
    /// `<enum extends="FooFlagBits">` entries find the right builder.
    flag_bits_to_flags: std.StringHashMapUnmanaged([]const u8) = .empty,
    builders: std.ArrayList(*EnumBuilder) = .empty,
    builder_index: std.StringHashMapUnmanaged(usize) = .empty,

    fn builderFor(self: *Registry_, name: []const u8, is_bitmask: bool, bit_width: u8) !*EnumBuilder {
        const key = self.flag_bits_to_flags.get(name) orelse name;
        if (self.builder_index.get(key)) |idx| return self.builders.items[idx];
        const b = try self.gpa.create(EnumBuilder);
        b.* = .{ .name = key, .is_bitmask = is_bitmask, .bit_width = bit_width };
        try self.builder_index.put(self.gpa, key, self.builders.items.len);
        try self.builders.append(self.gpa, b);
        return b;
    }
};

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

pub fn parse(gpa: std.mem.Allocator, xml: []const u8) !model.Registry {
    var registry = model.Registry{ .arena = std.heap.ArenaAllocator.init(gpa) };
    const arena = registry.arena.allocator();

    try parseConstants(arena, xml, &registry);
    try parseBasetypes(arena, xml, &registry);

    var reg = Registry_{ .gpa = arena };

    var handles: std.ArrayList(model.Handle) = .empty;
    var aggregates: std.ArrayList(model.AggType) = .empty;

    try parseTypes(arena, xml, &reg, &handles, &aggregates);
    try parseEnumsBlocks(arena, xml, &reg);
    try parseExtensionsAndFeatures(arena, xml, &reg);

    var enums: std.ArrayList(model.EnumType) = .empty;
    for (reg.builders.items) |b| {
        try enums.append(arena, .{
            .name = b.name,
            .is_bitmask = b.is_bitmask,
            .bit_width = b.bit_width,
            .values = try b.values.toOwnedSlice(arena),
        });
    }

    var commands: std.ArrayList(model.Command) = .empty;
    try parseCommands(arena, xml, &commands);

    registry.handles = try handles.toOwnedSlice(arena);
    registry.enums = try enums.toOwnedSlice(arena);
    registry.aggregates = try aggregates.toOwnedSlice(arena);
    registry.commands = try commands.toOwnedSlice(arena);
    return registry;
}

// ---------------------------------------------------------------------------
// `<enums name="API Constants">`
// ---------------------------------------------------------------------------

fn parseConstants(arena: std.mem.Allocator, xml: []const u8, registry: *model.Registry) !void {
    const start = std.mem.indexOf(u8, xml, "<enums name=\"API Constants\"") orelse return;
    const block = extractBlock(xml[start..], "<enums", "</enums>");

    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, block, pos, "<enum ")) |tag_start| {
        const header = scanTagHeader(block, tag_start + "<enum".len) orelse break;
        pos = header.tag_end + 1;
        const name = attrValue(header.attrs, "name") orelse continue;
        const raw_value = attrValue(header.attrs, "value") orelse continue;
        const value = parseCLiteralInt(raw_value) orelse continue;
        try registry.constants.put(arena, name, value);
    }
}

// ---------------------------------------------------------------------------
// `<type category="basetype">typedef <type>uint64_t</type> <name>VkDeviceSize</name>;</type>`
// ---------------------------------------------------------------------------

fn parseBasetypes(arena: std.mem.Allocator, xml: []const u8, registry: *model.Registry) !void {
    const types_block = extractBlock(xml, "<types", "</types>");
    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, types_block, pos, "<type")) |tag_start| {
        const header = scanTagHeader(types_block, tag_start + "<type".len) orelse break;
        if (header.self_closing) {
            pos = header.tag_end + 1;
            continue;
        }
        const body_end = findMatchingClose(types_block, header.tag_end + 1, "<type", "</type>") orelse break;
        const body = types_block[header.tag_end + 1 .. body_end];
        pos = body_end + "</type>".len;

        const category = attrValue(header.attrs, "category") orelse continue;
        if (!std.mem.eql(u8, category, "basetype")) continue;
        const name = sliceBetween(body, "<name>", "</name>") orelse continue;
        const inner = sliceBetween(body, "<type>", "</type>") orelse continue;
        const zig_base = mapPrimitive(inner) orelse continue;
        try registry.basetypes.put(arena, name, zig_base);
    }
}

fn mapPrimitive(c_name: []const u8) ?[]const u8 {
    const table = [_]struct { c: []const u8, zig: []const u8 }{
        .{ .c = "void", .zig = "anyopaque" },
        .{ .c = "char", .zig = "u8" },
        .{ .c = "float", .zig = "f32" },
        .{ .c = "double", .zig = "f64" },
        .{ .c = "int8_t", .zig = "i8" },
        .{ .c = "uint8_t", .zig = "u8" },
        .{ .c = "int16_t", .zig = "i16" },
        .{ .c = "uint16_t", .zig = "u16" },
        .{ .c = "int32_t", .zig = "i32" },
        .{ .c = "uint32_t", .zig = "u32" },
        .{ .c = "int64_t", .zig = "i64" },
        .{ .c = "uint64_t", .zig = "u64" },
        .{ .c = "size_t", .zig = "usize" },
        .{ .c = "int", .zig = "c_int" },
    };
    for (table) |entry| {
        if (std.mem.eql(u8, entry.c, c_name)) return entry.zig;
    }
    return null;
}

// ---------------------------------------------------------------------------
// `<types>`: handles, bitmask typedefs, enum forward-decls, struct/union
// definitions (with full member lists).
// ---------------------------------------------------------------------------

fn parseTypes(
    arena: std.mem.Allocator,
    xml: []const u8,
    reg: *Registry_,
    handles: *std.ArrayList(model.Handle),
    aggregates: *std.ArrayList(model.AggType),
) !void {
    const types_block = extractBlock(xml, "<types", "</types>");

    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, types_block, pos, "<type")) |tag_start| {
        const header = scanTagHeader(types_block, tag_start + "<type".len) orelse break;

        if (header.self_closing) {
            pos = header.tag_end + 1;
            try parseSelfClosingType(arena, reg, handles, header.attrs);
            continue;
        }

        const body_end = findMatchingClose(types_block, header.tag_end + 1, "<type", "</type>") orelse break;
        const body = types_block[header.tag_end + 1 .. body_end];
        pos = body_end + "</type>".len;

        if (attrValue(header.attrs, "alias") != null) continue;
        if (!apiIncludesVulkan(attrValue(header.attrs, "api"))) continue;

        const category = attrValue(header.attrs, "category") orelse continue;
        if (std.mem.eql(u8, category, "handle")) {
            const name = sliceBetween(body, "<name>", "</name>") orelse continue;
            const dispatchable = std.mem.indexOf(u8, body, "VK_DEFINE_NON_DISPATCHABLE_HANDLE") == null;
            try handles.append(arena, .{ .name = name, .dispatchable = dispatchable });
        } else if (std.mem.eql(u8, category, "bitmask")) {
            const flags_name = sliceBetween(body, "<name>", "</name>") orelse continue;
            const inner_type = sliceBetween(body, "<type>", "</type>") orelse "VkFlags";
            const bit_width: u8 = if (std.mem.eql(u8, inner_type, "VkFlags64")) 64 else 32;
            const bits_name = attrValue(header.attrs, "requires") orelse attrValue(header.attrs, "bitvalues");
            _ = try reg.builderFor(flags_name, true, bit_width);
            if (bits_name) |bn| try reg.flag_bits_to_flags.put(arena, bn, flags_name);
        } else if (std.mem.eql(u8, category, "struct") or std.mem.eql(u8, category, "union")) {
            const name = attrValue(header.attrs, "name") orelse continue;
            const members = try parseMembers(arena, body);
            try aggregates.append(arena, .{
                .name = name,
                .is_union = std.mem.eql(u8, category, "union"),
                .members = members,
            });
        }
        // "enum" category (forward decl) is handled by parseSelfClosingType
        // for the common self-closing form; a small number of enum decls
        // are non-self-closing with an empty body, so fall through here too.
        else if (std.mem.eql(u8, category, "enum")) {
            const name = attrValue(header.attrs, "name") orelse continue;
            _ = try reg.builderFor(name, false, 32);
        }
    }
}

fn parseSelfClosingType(
    arena: std.mem.Allocator,
    reg: *Registry_,
    handles: *std.ArrayList(model.Handle),
    attrs: []const u8,
) !void {
    if (attrValue(attrs, "alias") != null) return; // aliases are covered by their target
    if (!apiIncludesVulkan(attrValue(attrs, "api"))) return;
    const category = attrValue(attrs, "category") orelse return;
    const name = attrValue(attrs, "name") orelse return;
    if (std.mem.eql(u8, category, "enum")) {
        _ = try reg.builderFor(name, false, 32);
    } else if (std.mem.eql(u8, category, "handle")) {
        // Rare non-body form; dispatchability can't be determined here, so
        // default to non-dispatchable (u64) which is the more common case
        // for anything not using the VK_DEFINE_HANDLE macro body form.
        try handles.append(arena, .{ .name = name, .dispatchable = false });
    }
}

fn parseMembers(arena: std.mem.Allocator, struct_body: []const u8) ![]model.Member {
    var members: std.ArrayList(model.Member) = .empty;
    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, struct_body, pos, "<member")) |tag_start| {
        const header = scanTagHeader(struct_body, tag_start + "<member".len) orelse break;
        const body_end = std.mem.indexOfPos(u8, struct_body, header.tag_end + 1, "</member>") orelse break;
        const body = struct_body[header.tag_end + 1 .. body_end];
        pos = body_end + "</member>".len;

        if (!apiIncludesVulkan(attrValue(header.attrs, "api"))) continue;
        const member = parseTypeSlot(body, header.attrs) orelse continue;
        try members.append(arena, member);
    }
    return members.toOwnedSlice(arena);
}

// ---------------------------------------------------------------------------
// Top-level `<enums name="X" type="enum"|"bitmask">` blocks (scattered
// throughout the document, never nested inside `<types>`).
// ---------------------------------------------------------------------------

fn parseEnumsBlocks(arena: std.mem.Allocator, xml: []const u8, reg: *Registry_) !void {
    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, xml, pos, "<enums ")) |tag_start| {
        const header = scanTagHeader(xml, tag_start + "<enums".len) orelse break;
        if (header.self_closing) {
            pos = header.tag_end + 1;
            continue;
        }
        const body_end = std.mem.indexOfPos(u8, xml, header.tag_end + 1, "</enums>") orelse break;
        const body = xml[header.tag_end + 1 .. body_end];
        pos = body_end + "</enums>".len;

        const block_type = attrValue(header.attrs, "type") orelse continue;
        const is_bitmask = std.mem.eql(u8, block_type, "bitmask");
        if (!is_bitmask and !std.mem.eql(u8, block_type, "enum")) continue; // skips "API Constants"

        const name = attrValue(header.attrs, "name") orelse continue;
        const bit_width: u8 = if (attrValue(header.attrs, "bitwidth")) |w|
            (std.fmt.parseInt(u8, w, 10) catch 32)
        else
            32;

        const builder = try reg.builderFor(name, is_bitmask, bit_width);

        var vpos: usize = 0;
        while (std.mem.indexOfPos(u8, body, vpos, "<enum ")) |v_start| {
            const v_header = scanTagHeader(body, v_start + "<enum".len) orelse break;
            vpos = v_header.tag_end + 1;
            try addEnumValueFromAttrs(arena, builder, v_header.attrs, null);
        }
    }
}

/// Shared value-extraction for one `<enum ...>` entry, used both by base
/// `<enums>` blocks and by extension/feature `<require>` contributions.
/// `owning_ext_number` is the enclosing `<extension number="N">` (null
/// inside `<feature>` blocks, which always specify `extnumber` explicitly).
fn addEnumValueFromAttrs(
    arena: std.mem.Allocator,
    builder: *EnumBuilder,
    attrs: []const u8,
    owning_ext_number: ?i64,
) !void {
    if (attrValue(attrs, "alias") != null) return;
    const name = attrValue(attrs, "name") orelse return;

    if (attrValue(attrs, "bitpos")) |bp_raw| {
        const bitpos = std.fmt.parseInt(u6, bp_raw, 10) catch return;
        const value: i64 = @as(i64, 1) << bitpos;
        try builder.addValue(arena, name, value);
        return;
    }
    if (attrValue(attrs, "value")) |v_raw| {
        const value = parseCLiteralInt(v_raw) orelse return;
        try builder.addValue(arena, name, value);
        return;
    }
    if (attrValue(attrs, "offset")) |off_raw| {
        const offset = std.fmt.parseInt(i64, off_raw, 10) catch return;
        const ext_number = blk: {
            if (attrValue(attrs, "extnumber")) |n| break :blk std.fmt.parseInt(i64, n, 10) catch return;
            break :blk owning_ext_number orelse return;
        };
        const dir: i64 = if (attrValue(attrs, "dir")) |d| (if (std.mem.eql(u8, d, "-")) -1 else 1) else 1;
        const abs = dir * (1_000_000_000 + (ext_number - 1) * 1000 + offset);
        try builder.addValue(arena, name, abs);
        return;
    }
    // Plain spec-version / extension-name-string constants: not a type value, skip.
}

// ---------------------------------------------------------------------------
// `<feature>` and `<extensions>`/`<extension>` `<require>` blocks: these
// contribute additional values to enums/bitmasks declared elsewhere
// (extension-numbered VkResult/VkStructureType/*FlagBits entries). This is
// load-bearing, not a cosmetic extra -- engine.zig relies on several
// extension-contributed StructureType/Result values.
// ---------------------------------------------------------------------------

fn parseExtensionsAndFeatures(arena: std.mem.Allocator, xml: []const u8, reg: *Registry_) !void {
    try parseFeatureBlocks(arena, xml, reg);
    try parseExtensionBlocks(arena, xml, reg);
}

fn parseFeatureBlocks(arena: std.mem.Allocator, xml: []const u8, reg: *Registry_) !void {
    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, xml, pos, "<feature ")) |tag_start| {
        const header = scanTagHeader(xml, tag_start + "<feature".len) orelse break;
        if (header.self_closing) {
            pos = header.tag_end + 1;
            continue;
        }
        const body_end = std.mem.indexOfPos(u8, xml, header.tag_end + 1, "</feature>") orelse break;
        const body = xml[header.tag_end + 1 .. body_end];
        pos = body_end + "</feature>".len;
        if (!apiIncludesVulkan(attrValue(header.attrs, "api"))) continue;

        try scanEnumContributions(arena, reg, body, null);
    }
}

fn parseExtensionBlocks(arena: std.mem.Allocator, xml: []const u8, reg: *Registry_) !void {
    const start = std.mem.indexOf(u8, xml, "<extensions") orelse return;
    const extensions_block = extractBlock(xml[start..], "<extensions", "</extensions>");

    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, extensions_block, pos, "<extension ")) |tag_start| {
        const header = scanTagHeader(extensions_block, tag_start + "<extension".len) orelse break;
        if (header.self_closing) {
            pos = header.tag_end + 1;
            continue;
        }
        const body_end = std.mem.indexOfPos(u8, extensions_block, header.tag_end + 1, "</extension>") orelse break;
        const body = extensions_block[header.tag_end + 1 .. body_end];
        pos = body_end + "</extension>".len;

        if (attrValue(header.attrs, "supported")) |supported| {
            if (std.mem.eql(u8, supported, "disabled")) continue;
        }
        const number: ?i64 = if (attrValue(header.attrs, "number")) |n|
            (std.fmt.parseInt(i64, n, 10) catch null)
        else
            null;

        try scanEnumContributions(arena, reg, body, number);
    }
}

fn scanEnumContributions(arena: std.mem.Allocator, reg: *Registry_, body: []const u8, owning_ext_number: ?i64) !void {
    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, body, pos, "<enum ")) |tag_start| {
        const header = scanTagHeader(body, tag_start + "<enum".len) orelse break;
        pos = header.tag_end + 1;
        const extends = attrValue(header.attrs, "extends") orelse continue;
        // `extends` should always already have a builder from the <types>
        // pass; `false, 32` are just fallback defaults for the (unexpected)
        // case where it doesn't.
        const builder = try reg.builderFor(extends, false, 32);
        try addEnumValueFromAttrs(arena, builder, header.attrs, owning_ext_number);
    }
}

// ---------------------------------------------------------------------------
// `<commands>`
// ---------------------------------------------------------------------------

fn parseCommands(arena: std.mem.Allocator, xml: []const u8, commands: *std.ArrayList(model.Command)) !void {
    const commands_block = extractBlock(xml, "<commands", "</commands>");

    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, commands_block, pos, "<command")) |cmd_start| {
        const header = scanTagHeader(commands_block, cmd_start + "<command".len) orelse break;

        if (header.self_closing) {
            // Pure alias command (`<command name="X" alias="Y"/>`): the
            // aliased target is already covered under its own name.
            pos = header.tag_end + 1;
            continue;
        }

        const body_end = std.mem.indexOfPos(u8, commands_block, header.tag_end + 1, "</command>") orelse break;
        const body = commands_block[header.tag_end + 1 .. body_end];
        pos = body_end + "</command>".len;

        if (!apiIncludesVulkan(attrValue(header.attrs, "api"))) continue;

        const proto = sliceBetween(body, "<proto>", "</proto>") orelse continue;
        const c_name = sliceBetween(proto, "<name>", "</name>") orelse continue;
        const return_type = sliceBetween(proto, "<type>", "</type>") orelse "void";

        // <implicitexternsyncparams> is trailing prose wrapped in its own
        // <param> tags; truncate before it so it's never mistaken for a
        // real parameter.
        const scan_body = if (std.mem.indexOf(u8, body, "<implicitexternsyncparams>")) |idx|
            body[0..idx]
        else
            body;

        var params: std.ArrayList(model.Member) = .empty;
        var ppos: usize = 0;
        while (std.mem.indexOfPos(u8, scan_body, ppos, "<param")) |p_start| {
            const p_header = scanTagHeader(scan_body, p_start + "<param".len) orelse break;
            const p_body_end = std.mem.indexOfPos(u8, scan_body, p_header.tag_end + 1, "</param>") orelse break;
            const p_body = scan_body[p_header.tag_end + 1 .. p_body_end];
            ppos = p_body_end + "</param>".len;

            if (!apiIncludesVulkan(attrValue(p_header.attrs, "api"))) continue;
            const param = parseTypeSlot(p_body, p_header.attrs) orelse continue;
            try params.append(arena, param);
        }

        try commands.append(arena, .{
            .c_name = c_name,
            .return_type = return_type,
            .params = try params.toOwnedSlice(arena),
        });
    }
}

/// "vkCreateInstance" -> "createInstance" / "VkInstanceCreateInfo" -> "InstanceCreateInfo":
/// strip the leading "vk"/"Vk" and lowercase (commands) or keep (types) the
/// case of the first remaining character.
pub fn zigCommandName(buf: []u8, c_name: []const u8) []const u8 {
    std.debug.assert(std.mem.startsWith(u8, c_name, "vk"));
    const rest = c_name[2..];
    std.debug.assert(rest.len <= buf.len);
    @memcpy(buf[0..rest.len], rest);
    buf[0] = std.ascii.toLower(buf[0]);
    return buf[0..rest.len];
}

pub fn zigTypeName(c_name: []const u8) []const u8 {
    if (std.mem.startsWith(u8, c_name, "Vk")) return c_name[2..];
    return c_name;
}

test "zigCommandName strips leading vk and lowercases only the first letter" {
    var buf: [128]u8 = undefined;
    try std.testing.expectEqualStrings("createInstance", zigCommandName(&buf, "vkCreateInstance"));
}

test "zigTypeName strips leading Vk" {
    try std.testing.expectEqualStrings("InstanceCreateInfo", zigTypeName("VkInstanceCreateInfo"));
}

test "parseCLiteralInt handles plain, negative and bitwise-not forms" {
    try std.testing.expectEqual(@as(?i64, 256), parseCLiteralInt("256"));
    try std.testing.expectEqual(@as(?i64, -13), parseCLiteralInt("-13"));
    try std.testing.expectEqual(@as(?i64, @as(i64, std.math.maxInt(u32))), parseCLiteralInt("(~0U)"));
    try std.testing.expectEqual(@as(?i64, null), parseCLiteralInt("1000.0F"));
}

test "extension offset resolves to the documented absolute value" {
    // VK_ERROR_SURFACE_LOST_KHR: extension number 1, offset 0, dir "-" -> -1000000000
    var reg = Registry_{ .gpa = std.testing.allocator };
    defer {
        for (reg.builders.items) |b| std.testing.allocator.destroy(b);
        reg.builders.deinit(std.testing.allocator);
        reg.builder_index.deinit(std.testing.allocator);
        reg.flag_bits_to_flags.deinit(std.testing.allocator);
    }
    const builder = try reg.builderFor("VkResult", false, 32);
    defer builder.values.deinit(std.testing.allocator);
    defer builder.seen.deinit(std.testing.allocator);
    try addEnumValueFromAttrs(std.testing.allocator, builder, "offset=\"0\" extends=\"VkResult\" dir=\"-\" name=\"VK_ERROR_SURFACE_LOST_KHR\"", 1);
    try std.testing.expectEqual(@as(usize, 1), builder.values.items.len);
    try std.testing.expectEqual(@as(i64, -1_000_000_000), builder.values.items[0].value);
}

test "parseTypeSlot extracts pointer depth, const and array length" {
    const body = "const <type>char</type>*     <name>pApplicationName</name>";
    const member = parseTypeSlot(body, "optional=\"true\" len=\"null-terminated\"").?;
    try std.testing.expectEqualStrings("pApplicationName", member.name);
    try std.testing.expectEqualStrings("char", member.type.base);
    try std.testing.expectEqual(@as(u2, 1), member.type.pointer_depth);
    try std.testing.expect(member.type.is_const);
    try std.testing.expect(member.type.is_optional);
}

test "parseTypeSlot extracts symbolic array length" {
    const body = "<type>uint8_t</type>        <name>pipelineCacheUUID</name>[<enum>VK_UUID_SIZE</enum>]";
    const member = parseTypeSlot(body, "").?;
    try std.testing.expectEqualStrings("VK_UUID_SIZE", member.type.array_len.?);
}
