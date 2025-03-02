const std = @import("std");
const print = std.debug.print;
const Node = @import("types.zig").Node;
const Heap = @import("types.zig").Heap;

const HuffmanError = error{EmptyHeap};

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

    const nodesPtr = try allocator.alloc(Node, frequencyMap.count());
    defer allocator.free(nodesPtr);

    var heap = try buildHeap(allocator, &frequencyMap, nodesPtr);
    defer heap.deinit();
    while (heap.removeOrNull()) |item| {
        item.printInfo();
    }
    //build the huffman tree from heap
    //while heap doesnt have only 1 node remaining, do:
    //  pop 2 item from heap and merge them under non-leaf node, add the non-leaf node back to heap
    //end

}

//it's caller's responsibility to free the heap
//caller is managing the lifetime of the nodes
fn buildHeap(allocator: std.mem.Allocator, frequencyMap: *std.AutoHashMap(u8, u32), nodesPtr: []Node) !Heap {
    var heap = Heap.init(allocator, {});
    var it = frequencyMap.iterator();
    var idx: usize = 0;
    while (it.next()) |entry| : (idx += 1) {
        nodesPtr[idx] = Node{ .leafNode = .{ .charValue = entry.key_ptr.*, .freq = entry.value_ptr.* } };
        try heap.add(&nodesPtr[idx]);
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

//dont think encoding matters
// test "encoding_test" {
//     print("------------\n", .{});
//     const file = try std.fs.cwd().openFile("tests/book.txt", .{});
//     const ally = std.testing.allocator;
//     const raw_bytes = try file.reader().readAllAlloc(ally, 10000000);
//     defer ally.free(raw_bytes);
//     var codepoints = std.ArrayList(u32).init(ally);
//     defer codepoints.deinit();
//
//     var utf8 = (try std.unicode.Utf8View.init(raw_bytes)).iterator();
//     while (utf8.nextCodepointSlice()) |codepoint| {
//         std.debug.print("got codepoint {s}\n", .{codepoint});
//     }
// }
