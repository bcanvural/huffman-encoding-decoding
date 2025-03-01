const std = @import("std");
const print = std.debug.print;
const Node = @import("types.zig").Node;
const Heap = @import("types.zig").Heap;
const KV = @import("types.zig").KV;

const HuffmanError = error{MemoryError};

fn printMap(map: *std.AutoHashMap(u8, u32)) void {
    print("KEY | VALUE\n", .{});
    var it = map.iterator();
    while (it.next()) |k| {
        print("{c} | {d}\n", .{ k.key_ptr.*, k.value_ptr.* });
    }
}
fn processBook(allocator: std.mem.Allocator, book: []u8) !void {
    var frequencyMap = std.AutoHashMap(u8, u32).init(allocator);
    defer frequencyMap.deinit();
    for (book) |ch| {
        const entry = try frequencyMap.getOrPut(ch);
        if (entry.found_existing) {
            entry.value_ptr.* += 1;
        } else {
            entry.value_ptr.* = 1;
        }
    }
    // printMap(&frequencyMap);
    var heap = try buildPriorityQueue(allocator, &frequencyMap);
    defer heap.deinit();
    while (heap.removeOrNull()) |item| {
        print("key: {c}, value: {d}\n", .{ item.key, item.value });
    }
}

//it's caller's responsibility to free the heap
fn buildPriorityQueue(allocator: std.mem.Allocator, frequencyMap: *std.AutoHashMap(u8, u32)) !Heap {
    var heap = Heap.init(allocator, {});
    var it = frequencyMap.iterator();
    while (it.next()) |entry| {
        try heap.add(KV{
            .key = entry.key_ptr.*,
            .value = entry.value_ptr.*,
        });
    }
    return heap;
}

pub fn main() !void {}

test "file_test" {
    print("------------\n", .{});
    const file = try std.fs.cwd().openFile("tests/book.txt", .{});
    const ally = std.testing.allocator;
    const book = try file.reader().readAllAlloc(ally, 10000000);
    defer ally.free(book);
    try processBook(ally, book);
}
