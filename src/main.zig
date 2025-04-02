const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const print = std.debug.print;
const assert = std.debug.assert;
const FreqMap = @import("types.zig").FreqMap;
const Heap = @import("types.zig").Heap;
const HuffmanError = @import("types.zig").HuffmanError;
const HuffmanTree = @import("types.zig").HuffmanTree;
const Node = @import("types.zig").Node;

const MAX_FILE_SIZE: usize = 100000000;
const HEADER_DELIMITER: u8 = '#'; //we will write this twice after FreqMap to know freqmap ended.

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
    _ = try outputFile.write(&[_]u8{ HEADER_DELIMITER, HEADER_DELIMITER }); //writing twice
}

//returned bytes are owned by the caller, need to be freed with the same allocator
fn readCompressedFileHeader(allocator: mem.Allocator, inputFile: fs.File) ![]u8 {
    try inputFile.seekTo(0);
    var charList = std.ArrayList(u8).init(allocator);
    try inputFile.reader().readUntilDelimiterArrayList(&charList, HEADER_DELIMITER, 1024);
    return try charList.toOwnedSlice();
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

fn compress(
    allocator: mem.Allocator,
    ht: HuffmanTree,
    inputFile: fs.File,
    outputFile: fs.File,
) !void {
    try outputFile.seekFromEnd(0);
    var compressedList = std.ArrayList(u8).init(allocator); //we collect compressed chars here
    defer compressedList.deinit();
    var encodingsList = std.ArrayList(u8).init(allocator);
    defer encodingsList.deinit(); //we collect all encoding bits in order here
    //how many bits we processed in the last compressedChar, written as char in the last byte.
    //will be useful during decompression
    var lastProcessedBitCount: usize = 0; //how many bits in the last byte contains compressed bits
    while (true) {
        var fileCharBuf: [1024]u8 = undefined;
        const readCount = try inputFile.read(&fileCharBuf);
        try rawBytesToCompressedList(fileCharBuf[0..readCount], ht, &encodingsList, &compressedList);
        if (readCount < 1024) {
            //todo, this condition may not be sufficient to determine eof was reached
            break;
        }
    }
    //if we still have leftovers (we can, up to 8 items)
    if (encodingsList.items.len > 0) {
        lastProcessedBitCount = encodingsList.items.len; //remember this field! we'll write it to the outputfile so we can read it during decompression
        const compressed = bitStrToChar(encodingsList.items[0..encodingsList.items.len]);
        try compressedList.append(compressed);
    }
    try moveFileCursorToEndOfHeader(outputFile);
    const remainderInU8 = mod8RemainderToU8(lastProcessedBitCount);
    _ = try outputFile.write(&[_]u8{remainderInU8}); //writing to just after HEADER_DELIMITERs
    //write all the compressed chars
    //TODO don't keep all in memory, do partial writes
    try outputFile.seekFromEnd(0);
    try outputFile.writeAll(compressedList.items);
}

test "compress" {
    const allocator = std.testing.allocator;

    var freqMap = FreqMap.init(allocator);
    defer freqMap.deinit();
    try freqMap.put('a', 10);
    try freqMap.put('c', 1);
    try freqMap.put('b', 1);

    var ht = try HuffmanTree.init(allocator, &freqMap);
    defer ht.deinit();

    printMap(&ht.encodingMap);

    const inputFile = try openFile("tests/compresstest.txt", .{});
    defer inputFile.close();

    const outputFile = try fs.cwd().createFile("compresstestoutput", .{ .read = true });
    //will use the outputfile later so won't defer close it for now

    try serializeFreqMap(&freqMap, outputFile);

    try compress(allocator, ht, inputFile, outputFile);

    const header = try readCompressedFileHeader(allocator, outputFile);
    defer allocator.free(header);
    print("{s}\n", .{header});

    var deserializedFreqMap = try deserializeFrequencyMap(allocator, header);
    defer deserializedFreqMap.deinit();
    try std.testing.expectEqual(@as(u32, 10), deserializedFreqMap.get('a').?);
    try std.testing.expectEqual(@as(u32, 1), deserializedFreqMap.get('c').?);
    try std.testing.expectEqual(@as(u32, 1), deserializedFreqMap.get('b').?);

    try moveFileCursorToEndOfHeader(outputFile);
    const remainingBytes = try outputFile.readToEndAlloc(allocator, MAX_FILE_SIZE);
    defer allocator.free(remainingBytes);
    //encoding map is:
    // key: b value: 00
    // key: a value: 1
    // key: c value: 01
    // therefore we expect these bits:
    //11111111 11010000
    //last 2 0s are padding (lastProcessedBitCount should be 6)
    //so expected bytes are:
    //0x36 0xFF 0xD0
    //0x36 is equivalent to '6' as char byte
    try std.testing.expectEqual(@as(usize, 3), remainingBytes.len);
    try std.testing.expectEqual(@as(u8, '6'), remainingBytes[0]);
    try std.testing.expectEqual(@as(u8, 0xFF), remainingBytes[1]);
    try std.testing.expectEqual(@as(u8, 0xD0), remainingBytes[2]);

    //decompress
    outputFile.close();

    const decompressInput = try openFile("compresstestoutput", .{});
    defer decompressInput.close();

    const decompressOutput = try fs.cwd().createFile("decompressoutput", .{});
    defer decompressOutput.close();

    try decompress(allocator, ht, decompressInput, decompressOutput);
}

//Go through each byte, find its encoding from the encodingmap
//flatten each ending bit string to the encodingsList list
//if encodingsList surpassed >8 items consume and compress, collect compressed chars in compressedList
fn rawBytesToCompressedList(rawBytes: []u8, ht: HuffmanTree, encodingsList: *std.ArrayList(u8), compressedList: *std.ArrayList(u8)) !void {
    var bufIdx: usize = 0;
    while (bufIdx < rawBytes.len) : (bufIdx += 1) {
        const byte = rawBytes[bufIdx];
        const encoding = ht.encodingMap.get(byte) orelse {
            const representation = switch (byte) {
                '\n' => "newLine",
                '\t' => "tab",
                '\r' => "carriage return",
                else => &[_]u8{byte},
            };
            print("unaccounted byte: {s}\n", .{representation});
            return HuffmanError.ByteUnaccountedFor;
        };
        //flatten the encoding bits into encodingslist
        for (encoding) |bitStr| {
            try encodingsList.append(bitStr);
        }
        //if encodingsList has grown just above 8 we take a brake and compress those.
        //We'll only process 8 at a time, we don't have to worry about "remainders" just yet
        while (encodingsList.items.len >= 8) {
            const compressed = bitStrToChar(encodingsList.items[0..8]);
            try compressedList.append(compressed);
            shiftNthAndForwardsToBeginning(encodingsList, 8);
        }
    }
}

//pre: remainder is < 8
inline fn mod8RemainderToU8(remainder: usize) u8 {
    assert(remainder < 8);
    const nums = [_]u8{ '0', '1', '2', '3', '4', '5', '6', '7' };
    return nums[remainder];
}

//moves nth index and what comese after to the beginning of the array
fn shiftNthAndForwardsToBeginning(list: *std.ArrayList(u8), n: usize) void {
    const remainderSlice = list.items[n..list.items.len];
    mem.copyForwards(u8, list.items[0..remainderSlice.len], remainderSlice);
    list.shrinkRetainingCapacity(remainderSlice.len);
}

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

//adds bits of char as individual bytes and appends them to out param
//e.g. 0xFF -> '1' * 8 added to outEncodingList
fn charToBitChars(ch: u8, outEncodingList: *std.ArrayList(u8)) !void {
    for (0..8) |idx| {
        const mask = @as(u8, 1) << @intCast(7 - idx); //construct a byte where only the target idx is 1
        const masked = (ch & mask) >> @intCast(7 - idx); //find out what the target idx is, and shift it all way the way right to check what it is
        switch (masked) {
            0x00 => try outEncodingList.append('0'),
            0x01 => try outEncodingList.append('1'),
            else => unreachable,
        }
    }
    return;
}

fn moveFileCursorToEndOfHeader(file: fs.File) !void {
    try file.seekTo(0);
    var buf: [1024]u8 = undefined;
    //header ends with 2 HEADER_DELIMITER chars.
    //TODO make below more resillient to delimiter not existing
    while (true) {
        _ = try file.reader().readUntilDelimiter(&buf, HEADER_DELIMITER);
        //read 1 more, that one should also be HEADER_DELIMITER
        const anotherLimiter = try file.reader().readByte();
        if (anotherLimiter == HEADER_DELIMITER) {
            break;
        }
    }
}

test "moveFileCursorToEndOfHeader" {
    const testFileName = "moveFileCursorToEndOfHeader";
    const testFile = try fs.cwd().createFile(testFileName, .{ .read = true });
    defer {
        testFile.close();
        fs.cwd().deleteFile(testFileName) catch |err| {
            print("Caught error: {}\n", .{err});
        };
    }
    try testFile.writeAll(&[_]u8{ '1', '2', '3', '#', '#', '6' });
    try moveFileCursorToEndOfHeader(testFile);
    const aByte = try testFile.reader().readByte();
    try std.testing.expectEqual(@as(u8, '6'), aByte);
}

fn decompress(
    allocator: mem.Allocator,
    ht: HuffmanTree,
    inputFile: fs.File,
    outputFile: fs.File,
) !void {
    var encodingsList = std.ArrayList(u8).init(allocator);
    defer encodingsList.deinit();
    var decompressedCharList = std.ArrayList(u8).init(allocator);
    defer decompressedCharList.deinit();
    try moveFileCursorToEndOfHeader(inputFile);
    const lastProcessedBitCount = try inputFile.reader().readByte();
    print("lastProcessedBitCount: {c}\n", .{lastProcessedBitCount});
    while (true) {
        var fileCharBuf: [4096]u8 = undefined;
        const readCount = try inputFile.read(&fileCharBuf);
        //todo handle last byte of file OR write the lastProcessedBitCount to the header
        for (fileCharBuf[0..readCount]) |fileChar| {
            try charToBitChars(fileChar, &encodingsList);
        }
        //attempt to find the decompressed chars (we may not every time, but that's ok)
        while (try attemptFindLeafNodeCharFromEncodingBits(ht, &encodingsList, &decompressedCharList)) {
            print("Decompressed char count: {d}\n", .{decompressedCharList.items.len});
            printCharList(&decompressedCharList);
        }

        if (readCount < 1024) {
            break;
        }
    }

    try outputFile.writeAll(decompressedCharList.items); //todo do partial writes
}
fn printCharList(list: *std.ArrayList(u8)) void {
    for (list.items) |item| {
        print("{c}\n", .{item});
    }
}

//processes encodingsList, if a leaf node is found shrinks it (retaining capacity)
//writes decompressedChars to the decompressedCharList
fn attemptFindLeafNodeCharFromEncodingBits(ht: HuffmanTree, encodingsList: *std.ArrayList(u8), decompressedCharList: *std.ArrayList(u8)) !bool {
    //from encoding bits, find the leafnode and add its byte value to uncompressedList
    //remember the idx, and shift everything right of that idx to the beginning in encodingslist
    var current = ht.root;
    var idx: usize = 0;
    var leafNodeFound = false;
    loop: while (idx < encodingsList.items.len) {
        const bit = encodingsList.items[idx];
        switch (current.*) {
            .nonLeafNode => {
                switch (bit) {
                    '0' => current = current.*.nonLeafNode.left,
                    '1' => current = current.*.nonLeafNode.right,
                    else => unreachable,
                }
                idx += 1;
            },
            .leafNode => {
                break :loop;
            },
        }
    }
    if (current.* == .leafNode) {
        const decompressed = current.*.leafNode.charValue;
        try decompressedCharList.append(decompressed);
        if (idx != encodingsList.items.len - 1) {
            //there are still unprocessed items, let's move them to the beginning
            shiftNthAndForwardsToBeginning(encodingsList, idx);
        } else {
            //we processed everything, just shrink to 0
            encodingsList.shrinkRetainingCapacity(0);
        }
        leafNodeFound = true;
    }
    return leafNodeFound;
}

fn handleCommand(allocator: mem.Allocator, config: Config) !void {
    switch (config.operation) {
        Operation.Compression => {
            const inputFile = try openFile(config.inputFileName, .{ .mode = .read_only });
            defer inputFile.close();

            var freqMap = FreqMap.init(allocator);
            defer freqMap.deinit();
            while (true) {
                var buf: [1024]u8 = undefined;
                const readCount = try inputFile.read(&buf);
                try buildFrequencyMap(&freqMap, buf[0..readCount]);
                if (readCount < 1024) {
                    break;
                }
            }

            var ht = try HuffmanTree.init(allocator, &freqMap);
            defer ht.deinit();

            const outputFile = try fs.cwd().createFile(config.outputFileName, .{
                .read = true,
            }); //TODO support local and absolute file paths
            defer outputFile.close();

            try serializeFreqMap(&freqMap, outputFile);
            try compress(allocator, ht, inputFile, outputFile);
        },
        Operation.Decompression => {
            //deserializeFrequencyMap
            const inputFile = try openFile(config.inputFileName, .{ .mode = .read_only });
            defer inputFile.close();

            const headerBytes = try readCompressedFileHeader(allocator, inputFile);
            var freqMap = try deserializeFrequencyMap(allocator, headerBytes);
            defer freqMap.deinit();
            //read the remainder (last byte) todo
            //build HuffmanTree
            var ht = try HuffmanTree.init(allocator, &freqMap);
            defer ht.deinit();
            //
            const outputFile = openFile(config.outputFileName, .{ .mode = .read_write }) catch |err| switch (err) {
                fs.File.OpenError.FileNotFound => try fs.cwd().createFile(config.outputFileName, .{}),
                else => return err,
            };
            defer outputFile.close();
            try decompress(allocator, ht, inputFile, outputFile);
        },
    }
}
//Processes passed in bytes, updates frequency info in caller-managed word frequency map
fn buildFrequencyMap(freqMap: *FreqMap, bytes: []u8) !void {
    for (bytes) |ch| {
        const entry = try freqMap.getOrPut(ch);
        if (entry.found_existing) {
            entry.value_ptr.* += 1;
        } else {
            entry.value_ptr.* = 1;
        }
    }
}

fn openFile(filename: []const u8, flags: fs.File.OpenFlags) !fs.File {
    if (!mem.startsWith(u8, filename, "/")) {
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
pub const Config = struct {
    operation: Operation,
    inputFileName: []const u8,
    outputFileName: []const u8,
};

fn processArgs(args: [][:0]u8) !Config {
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
    return Config{
        .operation = operation,
        .inputFileName = inputFileName,
        .outputFileName = outputFileName,
    };
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(allocator, args);
    const config = processArgs(args) catch |err| switch (err) {
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

    print("Operation:{s}\n", .{config.operation.toStr()});
    print("Input file: {s}\n", .{config.inputFileName});
    print("Output file: {s}\n", .{config.outputFileName});

    try handleCommand(allocator, config);
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
    const config = try processArgs(&fakeArgs);
    try std.testing.expectEqual(Operation.Compression, config.operation);
    try std.testing.expectEqualStrings("tests/book.txt", config.inputFileName);
    try std.testing.expectEqualStrings("output", config.outputFileName);
}

test "build frequency map" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{ 'a', 'b', 'c', 'a' };
    var freqMap = FreqMap.init(allocator);
    try buildFrequencyMap(&freqMap, &bytes);
    defer freqMap.deinit();
    try std.testing.expectEqual(@as(u32, 2), freqMap.get('a').?);
    try std.testing.expectEqual(@as(u32, 1), freqMap.get('b').?);
    try std.testing.expectEqual(@as(u32, 1), freqMap.get('c').?);
}

test "small_heap" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{ 'a', 'a', 'a', 'c', 'b', 'b' };
    var freqMap = FreqMap.init(allocator);
    try buildFrequencyMap(&freqMap, &bytes);
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
    var freqMap = FreqMap.init(allocator);
    try buildFrequencyMap(&freqMap, &bytes);
    defer freqMap.deinit();
    var ht = try HuffmanTree.init(allocator, &freqMap);
    defer ht.deinit();
    printMap(&ht.encodingMap);
    ht.root.printSubtree();
}

test "ui example test" {
    const allocator = std.testing.allocator;

    var ht = try uiExampleHuffmanTree(allocator);
    defer ht.deinit();
    ht.root.printSubtree();
}

//test helper
fn uiExampleHuffmanTree(allocator: mem.Allocator) !HuffmanTree {
    var freqMap = try uiExampleFreqMap(allocator);
    defer freqMap.deinit();
    const ht = try HuffmanTree.init(allocator, &freqMap);
    return ht;
}
//test helper
fn uiExampleFreqMap(allocator: mem.Allocator) !FreqMap {
    var freqMap = FreqMap.init(allocator);
    try freqMap.put('C', 32);
    try freqMap.put('D', 42);
    try freqMap.put('E', 120);
    try freqMap.put('K', 7);
    try freqMap.put('L', 42);
    try freqMap.put('M', 24);
    try freqMap.put('U', 37);
    try freqMap.put('Z', 2);
    return freqMap;
}

test "file_test" {
    const file = try fs.cwd().openFile("tests/book.txt", .{});
    const ally = std.testing.allocator;
    const book = try file.reader().readAllAlloc(ally, 10000000);
    defer ally.free(book);
    try handleCommand(
        ally,
        .{ .inputFileName = "tests/book.txt", .operation = Operation.Compression, .outputFileName = "output" },
    );
}
test "charToBitChars" {
    const allocator = std.testing.allocator;
    var encodingList = std.ArrayList(u8).init(allocator);
    defer encodingList.deinit();

    const TestCase = struct {
        subject: u8,
        expected: []const u8,
    };
    const testCases = &[_]TestCase{
        .{
            .subject = 0xFF,
            .expected = &[_]u8{ '1', '1', '1', '1', '1', '1', '1', '1' },
        },
        .{
            .subject = 0x00,
            .expected = &[_]u8{ '0', '0', '0', '0', '0', '0', '0', '0' },
        },
        .{
            .subject = 0x0F,
            .expected = &[_]u8{ '0', '0', '0', '0', '1', '1', '1', '1' },
        },
        .{
            .subject = 0xF0,
            .expected = &[_]u8{ '1', '1', '1', '1', '0', '0', '0', '0' },
        },
        .{
            .subject = 0x44,
            .expected = &[_]u8{ '0', '1', '0', '0', '0', '1', '0', '0' },
        },
        .{
            .subject = 0xAC,
            .expected = &[_]u8{ '1', '0', '1', '0', '1', '1', '0', '0' },
        },
    };
    for (testCases) |testCase| {
        try charToBitChars(testCase.subject, &encodingList);
        try std.testing.expectEqualSlices(u8, testCase.expected, encodingList.items[0..encodingList.items.len]);
        encodingList.shrinkRetainingCapacity(0);
    }
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
fn printMap(map: *std.AutoHashMap(u8, []const u8)) void {
    var it = map.iterator();
    while (it.next()) |entry| {
        print("key: {c} value: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
}
test "serializeFreqMap / readCompressedFileHeader / deserializeFrequencyMap tests" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{ 'a', 'a', 'a', 'a', 'a', 'a', 'a', 'a', 'a', 'a', 'c', 'b', 'b' };
    var freqMap = FreqMap.init(allocator);
    try buildFrequencyMap(&freqMap, &bytes);
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
test "slicetest" {
    const testBytes = [_]u8{ 'b', '2', ';', 'a', '1', '0', ';', 'c', '1', ';' };
    const sliced = testBytes[1..2];
    print("{d}\n", .{try std.fmt.parseInt(u32, sliced, 10)});
}
test "rawBytesToCompressedList" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{ 'a', 'a', 'a', 'c', 'b', 'b', 'd', 'e', 'f', 'a' };
    //==Handcrafted example==
    //Running above bytes to generate huffman encodings we get below:
    // key: b value: 00
    // key: a value: 11
    // key: c value: 101
    // key: e value: 010
    // key: f value: 011
    // key: d value: 100
    //if we encode the bytes by hand using the encoding table above we get:
    //a  a  a  c   b  b  d   e   f   a
    //11 11 11 101 00 00 100 010 011 11
    //the compressed bits representation, grouped 8 at a time:
    //11111110 10000100 01001111
    //converting above bits to chars:
    //0xFE 0x84 0x4F
    var freqMap = FreqMap.init(allocator);
    try buildFrequencyMap(&freqMap, &bytes);
    defer freqMap.deinit();
    var ht = try HuffmanTree.init(allocator, &freqMap);
    defer ht.deinit();
    var compressedList = std.ArrayList(u8).init(allocator);
    defer compressedList.deinit();

    var encodingsList = std.ArrayList(u8).init(allocator);
    defer encodingsList.deinit();
    try rawBytesToCompressedList(&bytes, ht, &encodingsList, &compressedList);

    try std.testing.expectEqual(@as(usize, 3), compressedList.items.len);
    try std.testing.expectEqual(@as(u8, 0xFE), compressedList.items[0]);
    try std.testing.expectEqual(@as(u8, 0x84), compressedList.items[1]);
    try std.testing.expectEqual(@as(u8, 0x4F), compressedList.items[2]);
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
test "attemptFindLeafNodeCharFromEncodingBits" {
    const allocator = std.testing.allocator;
    var ht = try uiExampleHuffmanTree(allocator);
    defer ht.deinit();
    var encodingsList = std.ArrayList(u8).init(allocator);
    defer encodingsList.deinit();
    const encodingStr = &[_]u8{ '0', '1', '0', '0', '1', '0', '1', '0', '1', '1', '1', '0' };
    //expecting: E, U, L, E, C
    //in ui, D and L have the same value 42, in my program L is prioritized over D
    for (encodingStr) |ch| {
        try encodingsList.append(ch);
    }

    var decompressedList = std.ArrayList(u8).init(allocator);
    defer decompressedList.deinit();

    var foundE = try attemptFindLeafNodeCharFromEncodingBits(ht, &encodingsList, &decompressedList);
    try std.testing.expect(foundE);
    try std.testing.expectEqual(@as(usize, 1), decompressedList.items.len);
    try std.testing.expectEqual(@as(usize, encodingStr.len - 1), encodingsList.items.len);
    try std.testing.expectEqual('E', decompressedList.items[0]);

    const foundU = try attemptFindLeafNodeCharFromEncodingBits(ht, &encodingsList, &decompressedList);
    try std.testing.expect(foundU);
    try std.testing.expectEqual(@as(usize, 2), decompressedList.items.len);
    try std.testing.expectEqual(@as(usize, encodingStr.len - 4), encodingsList.items.len);
    try std.testing.expectEqual('U', decompressedList.items[1]);

    const foundL = try attemptFindLeafNodeCharFromEncodingBits(ht, &encodingsList, &decompressedList);
    try std.testing.expect(foundL);
    try std.testing.expectEqual(@as(usize, 3), decompressedList.items.len);
    try std.testing.expectEqual(@as(usize, encodingStr.len - 7), encodingsList.items.len);
    try std.testing.expectEqual('L', decompressedList.items[2]);

    foundE = try attemptFindLeafNodeCharFromEncodingBits(ht, &encodingsList, &decompressedList);
    try std.testing.expect(foundE);
    try std.testing.expectEqual(@as(usize, 4), decompressedList.items.len);
    try std.testing.expectEqual(@as(usize, encodingStr.len - 8), encodingsList.items.len);
    try std.testing.expectEqual('E', decompressedList.items[3]);

    const foundC = try attemptFindLeafNodeCharFromEncodingBits(ht, &encodingsList, &decompressedList);
    try std.testing.expect(foundC);
    try std.testing.expectEqual(@as(usize, 5), decompressedList.items.len);
    try std.testing.expectEqual(@as(usize, encodingStr.len - 12), encodingsList.items.len);
    try std.testing.expectEqual('C', decompressedList.items[4]);
}

test "absolutepathtest" {
    var out_buffer: [64]u8 = undefined;
    const path = try fs.cwd().realpath(".", &out_buffer);
    print("path: {s}\n", .{path});
}
