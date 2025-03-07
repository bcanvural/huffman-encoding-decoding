const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const print = std.debug.print;
const Node = @import("types.zig").Node;
const Heap = @import("types.zig").Heap;
const HuffmanTree = @import("types.zig").HuffmanTree;
const HuffmanError = @import("types.zig").HuffmanError;

const MAX_FILE_SIZE: usize = 100000;

fn printMap(map: *std.AutoHashMap(u8, u32)) void {
    print("KEY | VALUE\n", .{});
    var it = map.iterator();
    while (it.next()) |k| {
        print("{c} | {d}\n", .{ k.key_ptr.*, k.value_ptr.* });
    }
}

fn processBytes(allocator: mem.Allocator, bytes: []u8) !void {
    var frequencyMap = try buildFrequencyMap(allocator, bytes);
    defer frequencyMap.deinit();

    var heap = try Heap.init(allocator, &frequencyMap);
    defer heap.deinit();

    const ht = try HuffmanTree.init(allocator, &heap);
    defer ht.deinit();
    ht.root.printSubtree();
}

fn buildFrequencyMap(allocator: mem.Allocator, bytes: []u8) !std.AutoHashMap(u8, u32) {
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

fn openFile(filename: []const u8, flags: fs.File.OpenFlags) !fs.File {
    if (!std.mem.startsWith(u8, filename, "/")) {
        return try fs.cwd().openFile(filename, flags);
    } else {
        return try fs.openFileAbsolute(filename, flags);
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
    const file = try openFile(filename, .{ .mode = .read_only });
    const raw_bytes = try file.readToEndAlloc(allocator, MAX_FILE_SIZE);
    defer allocator.free(raw_bytes);
    try processBytes(allocator, raw_bytes);
}

test "processargs" {
    const allocator = std.testing.allocator;
    //printing pwd for debugging
    const pwd: []u8 = try allocator.alloc(u8, 100);
    defer allocator.free(pwd);
    _ = try fs.cwd().realpath(".", pwd);
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
    const allocator = std.testing.allocator;
    var bytes = [_]u8{ 'a', 'a', 'a', 'c', 'b', 'b' };
    var freqMap = try buildFrequencyMap(allocator, &bytes);
    defer freqMap.deinit();
    var heap = try Heap.init(allocator, &freqMap);
    defer heap.deinit();
    const expectedValues = &[_]u8{ 'c', 'b', 'a' };
    var idx: usize = 0;
    while (heap.pq.count() > 0) : (idx += 1) {
        const item = heap.pq.remove();
        try std.testing.expectEqual(expectedValues[idx], item.*.leafNode.charValue);
    }
}

test "huffman tree test" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{ 'a', 'a', 'a', 'c', 'b', 'b' };
    var freqMap = try buildFrequencyMap(allocator, &bytes);
    defer freqMap.deinit();
    var heap = try Heap.init(allocator, &freqMap);
    defer heap.deinit();
    const ht = try HuffmanTree.init(allocator, &heap);
    defer ht.deinit();
    ht.root.printSubtree();
}

test "ui example test" {
    const allocator = std.testing.allocator;

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

    var heap = try Heap.init(allocator, &freqMap);
    defer heap.deinit();

    const ht = try HuffmanTree.init(allocator, &heap);
    defer ht.deinit();
    ht.root.printSubtree();
}

test "file_test" {
    print("------------\n", .{});
    const file = try fs.cwd().openFile("tests/book.txt", .{});
    const ally = std.testing.allocator;
    const book = try file.reader().readAllAlloc(ally, 10000000);
    defer ally.free(book);
    try processBytes(ally, book);
}
