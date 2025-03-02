const std = @import("std");
const print = std.debug.print;
const Node = @import("types.zig").Node;
const Heap = @import("types.zig").Heap;

const HuffmanError = error{
    EmptyBytes,
    EmptyHeap,
};

fn printMap(map: *std.AutoHashMap(u8, u32)) void {
    print("KEY | VALUE\n", .{});
    var it = map.iterator();
    while (it.next()) |k| {
        print("{c} | {d}\n", .{ k.key_ptr.*, k.value_ptr.* });
    }
}
fn processBytes(allocator: std.mem.Allocator, bytes: []u8) !void {
    var frequencyMap = std.AutoHashMap(u8, u32).init(allocator);
    defer frequencyMap.deinit();
    for (bytes) |ch| {
        const entry = try frequencyMap.getOrPut(ch);
        if (entry.found_existing) {
            entry.value_ptr.* += 1;
        } else {
            entry.value_ptr.* = 1;
        }
    }

    if (frequencyMap.count() == 0) {
        return HuffmanError.EmptyBytes;
    }

    const nodesPtr = try allocator.alloc(Node, frequencyMap.count());
    defer allocator.free(nodesPtr);

    var heap = try buildHeap(allocator, &frequencyMap, nodesPtr);
    defer heap.deinit();

    var root: *Node = undefined;
    if (frequencyMap.count() == 1) {
        var it = frequencyMap.iterator();
        while (it.next()) |e| {
            root = try allocator.create(Node);
            root.* = Node{ .leafNode = .{
                .charValue = e.key_ptr.*,
                .freq = e.value_ptr.*,
            } };
            break;
        }
        defer allocator.destroy(root);
    } else {
        const nonLeafNodesPtr = try allocator.alloc(Node, frequencyMap.count() - 1);
        root = try buildHuffmanTree(&heap, nonLeafNodesPtr);
        defer allocator.free(nonLeafNodesPtr);
    }
    root.printSubtree();
}
//build the huffman tree from heap
//while heap doesnt have only 1 node remaining, do:
//  pop 2 item from heap and connect them under non-leaf node whose freq is sum of its children
//  add the new non-leaf node back to heap
//end
//
//any created non-leaf nodes are saved in nonLeafNodesPtr, caller's responsible for freeing those
fn buildHuffmanTree(heap: *Heap, nonLeafNodesPtr: []Node) !*Node {
    if (heap.count() == 0) {
        return HuffmanError.EmptyHeap; //shouldn't happen actually
    }

    var idx: usize = 0;
    while (heap.count() > 1) : (idx += 1) {
        const n1 = heap.removeOrNull().?; //we already checked in while clause
        const n2 = heap.removeOrNull().?; //we already checked in while clause
        const newNode: Node = Node{ .nonLeafNode = .{
            .freq = n1.getFreq() + n2.getFreq(),
            .left = n1,
            .right = n2,
        } };
        nonLeafNodesPtr[idx] = newNode;
        try heap.add(&nonLeafNodesPtr[idx]); //only array survives, program stack is gg after function call
    }
    return heap.removeOrNull().?; //already checked
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

//TODO debug
test "file_test" {
    print("------------\n", .{});
    const file = try std.fs.cwd().openFile("tests/book.txt", .{});
    const ally = std.testing.allocator;
    const book = try file.reader().readAllAlloc(ally, 10000000);
    defer ally.free(book);
    try processBytes(ally, book);
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
