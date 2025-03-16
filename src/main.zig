const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const print = std.debug.print;
const Node = @import("types.zig").Node;
const Heap = @import("types.zig").Heap;
const FreqMap = @import("types.zig").FreqMap;
const HuffmanTree = @import("types.zig").HuffmanTree;
const HuffmanError = @import("types.zig").HuffmanError;

const MAX_FILE_SIZE: usize = 100000000;
const HEADER_DELIMITER: u8 = '#';

fn printMap(map: *std.AutoHashMap(u8, []const u8)) void {
    var it = map.iterator();
    while (it.next()) |entry| {
        print("key: {c} value: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
}
//Format: [1byte key][up to 10 byte value][;][1byte key][up to 10 byte value][;]...
// 10 byte because 2^32 has 10 digits
// TODO encoding matters after all!
fn serializeFreqMap(freqMap: *FreqMap, outputFileName: []const u8) !void {
    const outputFile = try fs.cwd().createFile(outputFileName, .{}); //TODO handle absolute vs relative path
    defer outputFile.close();
    var it = freqMap.iterator();
    while (it.next()) |entry| {
        _ = try outputFile.write(&[_]u8{entry.key_ptr.*});
        var buffer: [10]u8 = undefined;
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
//Format: [1byte key][up to 10 byte value][;][1byte key][up to 10 byte value][;]...
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
        const valueBytes = bytes[(idx + 1)..subIdx];
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

//pre: header is already written to file
//walk through raw_bytes, serialize encoding for each byte into file.
// fn serializeEncoding(
//     ht: HuffmanTree,
//     raw_bytes: []u8,
//     outputFileName: []const u8,
// ) !void {
//     const outputFile = try openFile(outputFileName, .{ .mode = .{.read_write} });
//     defer outputFile.close();
//     //seek HEADER_DELIMITER, then append ? or just append.
//     //TODO: hmm do we need to pack the prefixtree(encodings) to bit strings?Not sure:
//     //"translate the prefixes into bit strings and pack them into bytes to achieve the compression"
//     //so: grab 8 bits from the pool?write it as char and continue?some encodings will straddle char boundries
//     const freqmap = try deserializeFrequencyMap(ht.allocator, raw_bytes);
//     defer freqmap.deinit();
//
//
// }

//TODO
//encodingmap contains byte array of bit strings (e.g. 1110 as 4 bytes: 1, 1, 1, and 0)
//we want to convert that to 1110 as bits, so in above example we'd fit 2 of such stirngs into 1 char (8 bytes)
//algo:
//read 1 byte from intput file
//find the encoding of that byte using encodingMap
//once we have the encoding string, do:
//  in a loop, collect 8 bits, write 1 char
//  last iteration we'll have <8 chars, write the remainder too. maybe we'll need to know when the encoding ended? maybe use another sentinel
//end
//looks like endinanness matters: maybe little endian would be more intuitive? think about decoding the bits too
//
fn encodingMaptoRawBytes(
    allocator: mem.Allocator,
    encodingMap: *std.AutoHashMap(u8, []const u8),
    inputFile: fs.File,
) ![]u8 {
    _ = allocator;
    _ = encodingMap;
    _ = inputFile;
}

fn processBytes(allocator: mem.Allocator, bytes: []u8, outputFileName: []const u8) !void {
    var freqMap = try buildFrequencyMap(allocator, bytes);
    defer freqMap.deinit();

    var ht = try HuffmanTree.init(allocator, &freqMap);
    defer ht.deinit();

    ht.root.printSubtree();
    printMap(&ht.encodingMap);

    try serializeFreqMap(&freqMap, outputFileName);
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

pub const Operation = enum {
    Compression,
    Decompression,
    pub fn toStr(self: Operation) []const u8 {
        switch (self) {
            Operation.Compression => return "Compression",
            Operation.Decompression => return "Decompression",
        }
    }
};
pub const ArgsResult = struct {
    operation: Operation,
    inputFileName: []u8,
    outputFileName: []u8,
};

fn processArgs(args: [][]u8) !ArgsResult {
    if (args.len < 4) {
        return HuffmanError.MissingFileNameError;
    }

    var operation: Operation = undefined;

    if (mem.eql(u8, args[1], "-c")) {
        operation = Operation.Compression;
    } else if (mem.eql(u8, args[1], "-d")) {
        operation = Operation.Decompression;
    } else {
        print("{s}\n", .{args[1]});
        return HuffmanError.InvalidOperationError;
    }

    const inputFileName = args[2];
    if (inputFileName.len == 0) {
        return HuffmanError.InvalidInputFileNameError;
    }
    const file = try openFile(inputFileName, .{ .mode = .read_only });
    defer file.close();
    const stat = try file.stat();
    if (stat.size == 0) {
        return HuffmanError.EmptyFileError;
    }
    const outputFileName = args[3];
    if (outputFileName.len == 0) {
        return HuffmanError.InvalidInputFileNameError;
    }
    return ArgsResult{
        .operation = operation,
        .inputFileName = inputFileName,
        .outputFileName = outputFileName,
    };
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(allocator, args);
    const argsResult = processArgs(args) catch |err| switch (err) {
        HuffmanError.InvalidInputFileNameError, HuffmanError.InvalidOutputFileNameError, HuffmanError.InvalidOperationError => {
            print("Usage: <program> <input_file> <output_file>\n", .{});
            return;
        },
        HuffmanError.EmptyFileError => {
            print("Input file is empty\n", .{});
            return;
        },
        else => return err,
    };

    print("Operation:{s}\n", .{argsResult.operation.toStr()});
    print("Input file: {s}\n", .{argsResult.inputFileName});
    print("Output file: {s}\n", .{argsResult.outputFileName});

    const file = try openFile(argsResult.inputFileName, .{ .mode = .read_only });
    const raw_bytes = try file.readToEndAlloc(allocator, MAX_FILE_SIZE);
    defer allocator.free(raw_bytes);
    try processBytes(allocator, raw_bytes, argsResult.outputFileName);
}

test "processargs" {
    const allocator = std.testing.allocator;
    var fakeArgs = [_][]u8{
        try allocator.dupe(u8, "huffman-encoding-decoding"),
        try allocator.dupe(u8, "-c"),
        try allocator.dupe(u8, "tests/book.txt"),
        try allocator.dupe(u8, "output"),
    };
    defer allocator.free(fakeArgs[0]);
    defer allocator.free(fakeArgs[1]);
    defer allocator.free(fakeArgs[2]);
    defer allocator.free(fakeArgs[3]);
    const argsResult = try processArgs(&fakeArgs);
    try std.testing.expectEqual(Operation.Compression, argsResult.operation);
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
    const nodes = try allocator.alloc(Node, freqMap.count());
    defer allocator.free(nodes);
    var heap = try Heap.init(allocator, &freqMap, nodes);
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
    var ht = try HuffmanTree.init(allocator, &freqMap);
    defer ht.deinit();
    printMap(&ht.encodingMap);
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

    var ht = try HuffmanTree.init(allocator, &freqMap);
    defer ht.deinit();
    ht.root.printSubtree();
}

test "file_test" {
    print("------------\n", .{});
    const file = try fs.cwd().openFile("tests/book.txt", .{});
    const ally = std.testing.allocator;
    const book = try file.reader().readAllAlloc(ally, 10000000);
    defer ally.free(book);
    try processBytes(ally, book, "output");
}
