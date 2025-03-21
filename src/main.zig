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
const HEADER_DELIMITER: u8 = '#'; //TODO: this will potentially collide with the content

fn printMap(map: *std.AutoHashMap(u8, []const u8)) void {
    var it = map.iterator();
    while (it.next()) |entry| {
        print("key: {c} value: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
}
//Format: [1byte key][up to 10 byte value][;][1byte key][up to 10 byte value][;]...
// 10 byte because 2^32 has 10 digits
fn serializeFreqMap(freqMap: *FreqMap, outputFile: fs.File) !void {
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
fn readCompressedFileHeader(allocator: mem.Allocator, inputFile: fs.File) ![]u8 {
    try inputFile.seekTo(0);
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
    const outputFile = try fs.cwd().createFile(outputFileName, .{
        .read = true,
    });
    defer outputFile.close();
    try serializeFreqMap(&freqMap, outputFile);
    const raw_bytes = try readCompressedFileHeader(allocator, outputFile);
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

//pre: freqmap was serialized in the header before
fn compress(
    allocator: mem.Allocator,
    ht: HuffmanTree,
    inputFile: fs.File,
    outputFile: fs.File,
) !void {
    var done = false;
    var compressedList = std.ArrayList(u8).init(allocator); //we collect compressed chars here
    defer compressedList.deinit();
    var encodingsList = std.ArrayList(u8).init(allocator);
    defer encodingsList.deinit();
    var remainder: usize = undefined; //how many bits we left untouched in the last compressedChar. Will be written as char in the last byte.
    while (!done) {
        var fileCharBuf: [1024]u8 = undefined;
        const readCount = try inputFile.read(&fileCharBuf);
        if (readCount < 1024) {
            done = true; //this is our last iteration
        }
        var bufIdx: usize = 0;

        while (bufIdx < fileCharBuf.len) : (bufIdx += 1) {
            const fileChar = fileCharBuf[bufIdx];
            const encoding = ht.encodingMap.get(fileChar) orelse return HuffmanError.ByteUnaccountedFor;
            //flatten the encoding bits into encodingslist
            for (encoding) |bitStr| {
                try encodingsList.append(bitStr);
            }
            //if encodingsList has grown just above 8 we take a brake and compress those.
            //We'll only process 8 at a time, we don't have to worry about "remainders" just yet
            while (encodingsList.items.len > 8) {
                const compressed = bitStrToChar(encodingsList.items[0..8]);
                try compressedList.append(compressed);
                shiftNthAndForwardsToBeginning(&encodingsList, 8);
            }
        }
    }
    //if we still have leftovers (we can, up to 8 items)
    if (encodingsList.items.len > 0) {
        print("There were some leftovers!\n", .{});
        const compressed = bitStrToChar(encodingsList.items[0..encodingsList.items.len]);
        try compressedList.append(compressed);
        remainder = encodingsList.items.len; //remember this field! we'll write it to the outputfile so we can read it during decompression
    }
    //write all the compressed chars
    //TODO don't keep all in memory, do partial writes
    try outputFile.seekFromEnd(0);
    try outputFile.writeAll(compressedList.items);
    const remainderInU8 = mod8RemainderToU8(remainder);
    _ = try outputFile.write(&[_]u8{remainderInU8});
}

fn mod8RemainderToU8(remainder: usize) u8 {
    const nums = [_]u8{ '0', '1', '2', '3', '4', '5', '6', '7' };
    return nums[remainder];
}

//moves nth index and what comese after to the beginning of the array
fn shiftNthAndForwardsToBeginning(list: *std.ArrayList(u8), n: usize) void {
    const remainderSlice = list.items[n..list.items.len];
    mem.copyForwards(u8, list.items[0..remainderSlice.len], remainderSlice);
    list.shrinkRetainingCapacity(remainderSlice.len);
}

test "shiftNthAndForwardsToBeginning" {
    const allocator = std.testing.allocator;
    var subject = std.ArrayList(u8).init(allocator);
    defer subject.deinit();

    try subject.append('1');
    try subject.append('2');
    try subject.append('3');
    try subject.append('4');

    shiftNthAndForwardsToBeginning(&subject, 2);

    try std.testing.expectEqual(@as(i32, 2), subject.items.len);
    try std.testing.expectEqual(@as(u8, '3'), subject.items[0]);
    try std.testing.expectEqual(@as(u8, '4'), subject.items[1]);

    try subject.append('1');
    try subject.append('2');
    try std.testing.expectEqual(@as(i32, 4), subject.items.len);

    shiftNthAndForwardsToBeginning(&subject, 2);
    try std.testing.expectEqual(@as(i32, 2), subject.items.len);
    try std.testing.expectEqual(@as(u8, '1'), subject.items[0]);
    try std.testing.expectEqual(@as(u8, '2'), subject.items[1]);
}

// pre: bitStr len is 8
// todo should this handle non-8 bit strings too?
fn bitStrToChar(bitStr: []const u8) u8 {
    var finalCh: u8 = 0;

    //idea: we start with all 0s, if we need to flip a bit to 1,
    //we first construct a mask to target and flip that bit.
    for (bitStr, 0..) |bit, idx| switch (bit) {
        '0' => {},
        '1' => {
            const mask: u8 = @as(u8, 1) << @intCast(7 - idx);
            finalCh |= mask;
        },
        else => unreachable,
    };
    return finalCh;
}

test "bitstrtochar" {
    const TestCase = struct {
        subject: []const u8,
        expected: u8,
    };
    const testCases = &[_]TestCase{
        .{
            .subject = &[_]u8{ '1', '1', '1', '1', '1', '1', '1', '1' },
            .expected = 0xFF,
        },
        .{
            .subject = &[_]u8{ '0', '0', '0', '1', '1', '1', '1', '1' },
            .expected = 0x1F,
        },
        .{
            .subject = &[_]u8{ '0', '0', '0', '0', '0', '0', '0', '1' },
            .expected = 0x01,
        },
        .{
            .subject = &[_]u8{ '0', '0', '0', '0', '1', '0', '1', '1' },
            .expected = 0x0B,
        },
        .{
            .subject = &[_]u8{ '0', '0', '0', '0', '0', '0', '0', '0' },
            .expected = 0x00,
        },
    };
    for (testCases) |testCase| {
        try std.testing.expectEqual(testCase.expected, bitStrToChar(testCase.subject));
    }
}

fn processBytes(allocator: mem.Allocator, bytes: []u8, outputFileName: []const u8) !void {
    var freqMap = try buildFrequencyMap(allocator, bytes);
    defer freqMap.deinit();

    var ht = try HuffmanTree.init(allocator, &freqMap);
    defer ht.deinit();

    ht.root.printSubtree();
    printMap(&ht.encodingMap);

    //TODO file management is a bit all over the place
    const inputFile = try openFile("tests/book.txt", .{ .mode = .read_only });
    defer inputFile.close();

    const outputFile = try fs.cwd().createFile(outputFileName, .{
        .read = true,
    });
    defer outputFile.close();
    try serializeFreqMap(&freqMap, outputFile);
    try compress(allocator, ht, inputFile, outputFile);
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

fn processArgs(args: [][:0]u8) !ArgsResult {
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
    var fakeArgs = [_][:0]u8{
        try allocator.dupeZ(u8, "huffman-encoding-decoding"),
        try allocator.dupeZ(u8, "-c"),
        try allocator.dupeZ(u8, "tests/book.txt"),
        try allocator.dupeZ(u8, "output"),
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
