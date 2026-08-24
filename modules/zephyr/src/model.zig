const std = @import("std");

/// A resolved reference to a type used as a struct/union member or a command parameter.
pub const TypeRef = struct {
    /// The C base type name, e.g. "VkInstance", "uint32_t", "void", "char".
    base: []const u8,
    /// Number of `*` indirections (0 = value, 1 = pointer, 2 = pointer-to-pointer).
    pointer_depth: u2 = 0,
    /// Whether the pointee (or the value itself, for depth 0) was declared `const`.
    is_const: bool = false,
    /// Whether the vk.xml attribute `optional="true"` was present.
    is_optional: bool = false,
    /// Fixed-size C array length, e.g. "4" or the symbolic name "VK_UUID_SIZE" (resolved
    /// against `Registry.constants` at emit time). Null if this is not an array member.
    array_len: ?[]const u8 = null,
};

pub const Member = struct {
    name: []const u8,
    type: TypeRef,
};

pub const EnumValue = struct {
    name: []const u8,
    value: i64,
};

pub const Handle = struct {
    name: []const u8,
    dispatchable: bool,
};

pub const EnumType = struct {
    name: []const u8,
    is_bitmask: bool,
    bit_width: u8, // 32 or 64
    values: []EnumValue,
};

pub const AggType = struct {
    name: []const u8,
    is_union: bool,
    members: []Member,
};

pub const Command = struct {
    c_name: []const u8,
    return_type: []const u8, // "void" or a Vk*/base type name
    params: []Member,
};

pub const Registry = struct {
    arena: std.heap.ArenaAllocator,
    /// Name -> value, from `<enums name="API Constants">` plus VK_TRUE/VK_FALSE etc.
    constants: std.StringHashMapUnmanaged(i64) = .empty,
    /// Name -> underlying primitive Zig type, from `<type category="basetype">`.
    basetypes: std.StringHashMapUnmanaged([]const u8) = .empty,
    handles: []Handle = &.{},
    enums: []EnumType = &.{},
    aggregates: []AggType = &.{},
    commands: []Command = &.{},

    pub fn deinit(self: *Registry) void {
        self.arena.deinit();
    }
};
