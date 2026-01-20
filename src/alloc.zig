//! Allocator wrapper for Lua VM integration.
//!
//! This module provides a C-compatible allocator function that wraps Zig's allocator
//! interface. The Zig allocator must be passed as a pointer to maintain compatibility
//! with Lua's C-based memory management system.

const std = @import("std");
const Allocator = std.mem.Allocator;
const lua_alignment = std.mem.Alignment.fromByteUnits(@max(@alignOf(std.c.max_align_t), 16));
const Header = extern struct {
    payload_len: usize,
};
const header_size: usize = std.mem.alignForward(usize, @sizeOf(Header), lua_alignment.toByteUnits());

/// Lua allocator function that wraps a Zig allocator.
///
/// # Arguments
/// - `ptr` - a pointer to the block being allocated/reallocated/freed.
/// - `osize` - the original size of the block or some code about what is being allocated
/// - `nsize` - the new size of the block.
pub fn alloc(ud: ?*anyopaque, ptr: ?*anyopaque, osize: usize, nsize: usize) callconv(.c) ?*anyopaque {
    _ = osize;
    // Lua assumes the following behavior from the allocator function:
    // - When nsize is zero, the allocator must behave like free and return NULL.
    // - When nsize is not zero, the allocator must behave like realloc.
    //   The allocator returns NULL if and only if it cannot fulfill the request.
    // Lua assumes that the allocator never fails when osize >= nsize.

    // realloc requests a new byte size for an existing allocation, which can be larger, smaller,
    // or the same size as the old memory allocation.
    // If `new_n` is 0, this is the same as free and it always succeeds.
    // `old_mem` may have length zero, which makes a new allocation.
    // See https://ziglang.org/documentation/0.14.1/std/#std.mem.Allocator.realloc
    const allocator: *const Allocator = @ptrCast(@alignCast(ud.?));
    const ret_addr = @returnAddress();

    if (nsize == 0) {
        if (ptr) |old_ptr| {
            const old_user_ptr = @as([*]u8, @ptrCast(old_ptr));
            const old_base_ptr = old_user_ptr - header_size;
            const header_ptr: *Header = @ptrCast(@alignCast(old_base_ptr));
            const old_total = header_size + header_ptr.payload_len;
            const old_slice = old_base_ptr[0..old_total];
            allocator.rawFree(old_slice, lua_alignment, ret_addr);
        }
        return null;
    }

    if (ptr == null) {
        const new_total = header_size + nsize;
        const new_base_ptr = allocator.rawAlloc(new_total, lua_alignment, ret_addr) orelse return null;
        const header_ptr: *Header = @ptrCast(@alignCast(new_base_ptr));
        header_ptr.payload_len = nsize;
        const new_user_ptr = new_base_ptr + header_size;
        return @ptrCast(new_user_ptr);
    }

    const old_user_ptr = @as([*]u8, @ptrCast(ptr.?));
    const old_base_ptr = old_user_ptr - header_size;
    const header_ptr: *Header = @ptrCast(@alignCast(old_base_ptr));
    const old_payload_len = header_ptr.payload_len;
    const old_total = header_size + old_payload_len;
    const old_slice = old_base_ptr[0..old_total];
    const new_total = header_size + nsize;

    if (allocator.rawResize(old_slice, lua_alignment, new_total, ret_addr)) {
        header_ptr.payload_len = nsize;
        return @ptrCast(old_user_ptr);
    }

    if (allocator.rawRemap(old_slice, lua_alignment, new_total, ret_addr)) |new_base_ptr| {
        const new_header_ptr: *Header = @ptrCast(@alignCast(new_base_ptr));
        new_header_ptr.payload_len = nsize;
        const new_user_ptr = new_base_ptr + header_size;
        return @ptrCast(new_user_ptr);
    }

    if (nsize <= old_payload_len) {
        return @ptrCast(old_user_ptr);
    }

    const new_base_ptr = allocator.rawAlloc(new_total, lua_alignment, ret_addr) orelse return null;
    const new_header_ptr: *Header = @ptrCast(@alignCast(new_base_ptr));
    new_header_ptr.payload_len = nsize;
    const new_user_ptr = new_base_ptr + header_size;
    const old_user_slice = old_user_ptr[0..old_payload_len];
    @memcpy(new_user_ptr[0..old_payload_len], old_user_slice);
    allocator.rawFree(old_slice, lua_alignment, ret_addr);
    return @ptrCast(new_user_ptr);
}
