const std = @import("std");
const print = std.debug.print;
const Node = @import("types.zig").Node;
const Heap = @import("types.zig").Heap;

const HuffmanError = error{
    EmptyBytes,
    EmptyHeap,
    MissingFileNameError,
    EmptyFileError,
    InvalidFileNameError,
};

fn printMap(map: *std.AutoHashMap(u8, u32)) void {
    print("KEY | VALUE\n", .{});
    var it = map.iterator();
    while (it.next()) |k| {
        print("{c} | {d}\n", .{ k.key_ptr.*, k.value_ptr.* });
    }
}
fn processBytes(allocator: std.mem.Allocator, bytes: []u8) !void {
    var frequencyMap = try buildFrequencyMap(allocator, bytes);
    defer frequencyMap.deinit();

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
        root.printSubtree();
    } else {
        const nonLeafNodesPtr = try allocator.alloc(Node, frequencyMap.count() - 1);
        root = try buildHuffmanTree(&heap, nonLeafNodesPtr);
        defer allocator.free(nonLeafNodesPtr);
        root.printSubtree();
    }
}

fn buildFrequencyMap(allocator: std.mem.Allocator, bytes: []u8) !std.AutoHashMap(u8, u32) {
    var frequencyMap = std.AutoHashMap(u8, u32).init(allocator);
    for (bytes) |ch| {
        const entry = try frequencyMap.getOrPut(ch);
        if (entry.found_existing) {
            entry.value_ptr.* += 1;
        } else {
            entry.value_ptr.* = 1;
        }
    }
    return frequencyMap;
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
        try heap.add(&nodesPtr[idx]); //we write the address within the array, array is what survives!
    }
    return heap;
}

fn openFile(filename: []const u8, flags: std.fs.File.OpenFlags) !std.fs.File {
    if (!std.mem.startsWith(u8, filename, "/")) {
        return try std.fs.cwd().openFile(filename, flags);
    } else {
        return try std.fs.openFileAbsolute(filename, flags);
    }
}

fn processArgs(args: [][]u8) ![]u8 {
    if (args.len < 2) {
        return HuffmanError.MissingFileNameError;
    }
    const filename = args[1];
    if (filename.len == 0) {
        return HuffmanError.InvalidFileNameError;
    }
    const file = try openFile(filename, .{ .mode = .read_only });
    defer file.close();
    const stat = try file.stat();
    if (stat.size == 0) {
        return HuffmanError.EmptyFileError;
    }
    return filename;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(allocator, args);
    const filename = try processArgs(args);
    print("Processing {s}...\n", .{filename});
}

test "processargs" {
    const allocator = std.testing.allocator;
    //printing pwd for debugging
    const pwd: []u8 = try allocator.alloc(u8, 100);
    defer allocator.free(pwd);
    _ = try std.fs.cwd().realpath(".", pwd);
    //
    print("pwd: {s}\n", .{pwd});
    var fakeArgs = [_][]u8{
        try allocator.dupe(u8, "huffman-encoding-decoding"),
        try allocator.dupe(u8, "tests/book.txt"),
    };
    defer allocator.free(fakeArgs[0]);
    defer allocator.free(fakeArgs[1]);
    const filename = try processArgs(&fakeArgs);
    try std.testing.expectEqualStrings("tests/book.txt", filename);
}

test "build frequency map" {
    var bytes = [_]u8{ 'a', 'b', 'c', 'a' };
    var freqMap = try buildFrequencyMap(std.testing.allocator, &bytes);
    defer freqMap.deinit();
    try std.testing.expectEqual(@as(u32, 2), freqMap.get('a').?);
    try std.testing.expectEqual(@as(u32, 1), freqMap.get('b').?);
    try std.testing.expectEqual(@as(u32, 1), freqMap.get('c').?);
}

test "small_heap" {
    var allocator = std.testing.allocator;
    var bytes = [_]u8{ 'a', 'a', 'a', 'c', 'b', 'b' };
    var freqMap = try buildFrequencyMap(allocator, &bytes);
    defer freqMap.deinit();
    const nodesPtr = try allocator.alloc(Node, freqMap.count());
    defer allocator.free(nodesPtr);
    var heap = try buildHeap(std.testing.allocator, &freqMap, nodesPtr);
    defer heap.deinit();
    const expectedValues = &[_]u8{ 'c', 'b', 'a' };
    var idx: usize = 0;
    while (heap.count() > 0) : (idx += 1) {
        const item = heap.remove();
        try std.testing.expectEqual(expectedValues[idx], item.*.leafNode.charValue);
    }
}

test "huffman tree test" {
    var allocator = std.testing.allocator;
    var bytes = [_]u8{ 'a', 'a', 'a', 'c', 'b', 'b' };
    var freqMap = try buildFrequencyMap(allocator, &bytes);
    defer freqMap.deinit();
    const nodesPtr = try allocator.alloc(Node, freqMap.count());
    defer allocator.free(nodesPtr);
    var heap = try buildHeap(std.testing.allocator, &freqMap, nodesPtr);
    defer heap.deinit();
    const nonLeafNodesPtr = try allocator.alloc(Node, freqMap.count() - 1);
    const root = try buildHuffmanTree(&heap, nonLeafNodesPtr);
    defer allocator.free(nonLeafNodesPtr);
    root.printSubtree();
}

test "ui example test" {
    var allocator = std.testing.allocator;

    var freqMap = std.AutoHashMap(u8, u32).init(allocator);
    defer freqMap.deinit();
    try freqMap.put('C', 32);
    try freqMap.put('D', 42);
    try freqMap.put('E', 120);
    try freqMap.put('K', 7);
    try freqMap.put('L', 42);
    try freqMap.put('M', 24);
    try freqMap.put('U', 37);
    try freqMap.put('Z', 2);

    const nodesPtr = try allocator.alloc(Node, freqMap.count());
    defer allocator.free(nodesPtr);

    var heap = try buildHeap(allocator, &freqMap, nodesPtr);
    defer heap.deinit();

    const nonLeafNodesPtr = try allocator.alloc(Node, freqMap.count() - 1);
    const root = try buildHuffmanTree(&heap, nonLeafNodesPtr);
    defer allocator.free(nonLeafNodesPtr);
    root.printSubtree();
}

test "file_test" {
    print("------------\n", .{});
    const file = try std.fs.cwd().openFile("tests/book.txt", .{});
    const ally = std.testing.allocator;
    const book = try file.reader().readAllAlloc(ally, 10000000);
    defer ally.free(book);
    try processBytes(ally, book);
}
