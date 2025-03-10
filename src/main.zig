const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const print = std.debug.print;
const Node = @import("types.zig").Node;
const Heap = @import("types.zig").Heap;
const FreqMap = @import("types.zig").FreqMap;
const HuffmanTree = @import("types.zig").HuffmanTree;
const HuffmanError = @import("types.zig").HuffmanError;

const MAX_FILE_SIZE: usize = 100000;
const HEADER_DELIMITER: u8 = '#';

//Format: [1byte key][up to 4 byte value][;][1byte key][up to 4 byte value][;]...
fn serializeFreqMap(freqMap: *FreqMap, outputFileName: []const u8) !void {
    const outputFile = try fs.cwd().createFile(outputFileName, .{});
    var it = freqMap.iterator();
    while (it.next()) |entry| {
        _ = try outputFile.write(&[_]u8{entry.key_ptr.*});
        var buffer: [4]u8 = undefined;
        const valueStr = try std.fmt.bufPrint(&buffer, "{}", .{entry.value_ptr.*});
        _ = try outputFile.write(valueStr);
        _ = try outputFile.write(";");
    }
    _ = try outputFile.write(&[_]u8{HEADER_DELIMITER});
}

//returned bytes are owned by the caller, need to be freed with the same allocator
fn readCompressedFileHeader(allocator: mem.Allocator, inputFileName: []const u8) ![]u8 {
    const inputFile = try openFile(inputFileName, .{ .mode = .read_only });
    var charList = std.ArrayList(u8).init(allocator);
    try inputFile.reader().readUntilDelimiterArrayList(&charList, HEADER_DELIMITER, 1024);
    return try charList.toOwnedSlice();
}

test "serializeFreqMap / readCompressedFileHeader / deserializeFrequencyMap tests" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{ 'a', 'a', 'a', 'a', 'a', 'a', 'a', 'a', 'a', 'a', 'c', 'b', 'b' };
    var freqMap = try buildFrequencyMap(allocator, &bytes);
    defer freqMap.deinit();
    const outputFileName = "serializeFreqMapTest";
    try serializeFreqMap(&freqMap, outputFileName);
    const raw_bytes = try readCompressedFileHeader(allocator, outputFileName);
    defer allocator.free(raw_bytes);
    const expected_bytes = [_]u8{ 'b', '2', ';', 'a', '1', '0', ';', 'c', '1', ';' };
    try std.testing.expectEqual(expected_bytes.len, raw_bytes.len);
    for (0..expected_bytes.len) |idx| {
        try std.testing.expectEqual(expected_bytes[idx], raw_bytes[idx]);
    }
    var deserializedFreqMap = try deserializeFrequencyMap(allocator, raw_bytes);
    defer deserializedFreqMap.deinit();

    try std.testing.expectEqual(@as(u32, 2), deserializedFreqMap.get('b').?);
    try std.testing.expectEqual(@as(u32, 10), deserializedFreqMap.get('a').?);
    try std.testing.expectEqual(@as(u32, 1), deserializedFreqMap.get('c').?);
}

//parses the word frequency map from a previously compressed file
//Format: [1byte key][up to 4 byte value][;][1byte key][up to 4 byte value][;]...
fn deserializeFrequencyMap(allocator: mem.Allocator, bytes: []u8) !FreqMap {
    if (bytes.len == 0) {
        return HuffmanError.FileHeaderParseError;
    }
    var idx: usize = 0;
    var freqmap = FreqMap.init(allocator);
    while (idx < bytes.len) {
        var subIdx = idx;
        var testvar = bytes[subIdx];
        while (testvar != ';') {
            subIdx += 1;
            if (subIdx == bytes.len) {
                return HuffmanError.FileHeaderParseError;
            }
            testvar = bytes[subIdx];
        }
        const keyByte = bytes[idx];
        print("subIdx is: {d}\n", .{subIdx});
        const valueBytes = bytes[(idx + 1)..subIdx];
        print("valuebytes is: {s}\n", .{valueBytes});
        const value = try std.fmt.parseInt(u32, valueBytes, 10);
        try freqmap.put(keyByte, value);
        idx = subIdx + 1;
    }
    return freqmap;
}

test "slicetest" {
    const testBytes = [_]u8{ 'b', '2', ';', 'a', '1', '0', ';', 'c', '1', ';' };
    const sliced = testBytes[1..2];
    print("{d}\n", .{try std.fmt.parseInt(u32, sliced, 10)});
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
//operates on the input file's text to construct the word frequency map for the first time.
fn buildFrequencyMap(allocator: mem.Allocator, bytes: []u8) !FreqMap {
    var frequencyMap = FreqMap.init(allocator);
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

pub const ArgsResult = struct {
    inputFileName: []u8,
    outputFileName: []u8,
};

fn processArgs(args: [][]u8) !ArgsResult {
    if (args.len < 3) {
        return HuffmanError.MissingFileNameError;
    }
    const inputFileName = args[1];
    if (inputFileName.len == 0) {
        return HuffmanError.InvalidInputFileNameError;
    }
    const file = try openFile(inputFileName, .{ .mode = .read_only });
    defer file.close();
    const stat = try file.stat();
    if (stat.size == 0) {
        return HuffmanError.EmptyFileError;
    }
    const outputFileName = args[2];
    if (outputFileName.len == 0) {
        return HuffmanError.InvalidInputFileNameError;
    }
    return ArgsResult{
        .inputFileName = inputFileName,
        .outputFileName = outputFileName,
    };
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(allocator, args);
    const argsResult = processArgs(args) catch |err| switch (err) {
        HuffmanError.InvalidInputFileNameError, HuffmanError.InvalidOutputFileNameError => print("Usage: <program> <input_file> <output_file>\n", .{}),
        HuffmanError.EmptyFileError => print("Input file is empty\n", .{}),
        else => return err,
    };
    print("Processing {s}...\n", .{argsResult.inputFileName});
    const file = try openFile(argsResult.inputFileName, .{ .mode = .read_only });
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
        try allocator.dupe(u8, "output"),
    };
    defer allocator.free(fakeArgs[0]);
    defer allocator.free(fakeArgs[1]);
    defer allocator.free(fakeArgs[2]);
    const argsResult = try processArgs(&fakeArgs);
    try std.testing.expectEqualStrings("tests/book.txt", argsResult.inputFileName);
    try std.testing.expectEqualStrings("output", argsResult.outputFileName);
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

    var freqMap = FreqMap.init(allocator);
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
