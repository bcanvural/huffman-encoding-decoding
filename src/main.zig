const std = @import("std");
const print = std.debug.print;
const Node = @import("types.zig").Node;

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
    printMap(&frequencyMap);
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
