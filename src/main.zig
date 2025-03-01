const std = @import("std");
const print = std.debug.print;
const Node = @import("types.zig").Node;
const Heap = @import("types.zig").Heap;

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
        if (frequencyMap.get(ch)) |count| {
            try frequencyMap.put(ch, count + 1);
        } else {
            try frequencyMap.put(ch, 1);
        }
    }
    // printMap(&frequencyMap);
    var heap = try buildPriorityQueue(allocator, &frequencyMap);
    defer heap.deinit();
    var it = heap.iterator();
    while (it.next()) |item| {
        print("key: {c}, value: {d}", .{ item.key_ptr.*, item.value_ptr.* });
    }
}

//it's caller's responsibility to free the heap
inline fn buildPriorityQueue(allocator: std.mem.Allocator, frequencyMap: *std.AutoHashMap(u8, u32)) !*Heap {
    var it = frequencyMap.iterator();
    var heap = Heap.init(allocator, {});
    while (it.next()) |entry| {
        try heap.add(&entry);
    }
    return &heap;
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
