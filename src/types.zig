const std = @import("std");
const print = std.debug.print;
const mem = std.mem;

pub const HuffmanError = error{
    EmptyBytes,
    EmptyHeap,
    MissingFileNameError,
    EmptyFileError,
    InvalidInputFileNameError,
    InvalidOutputFileNameError,
    FileHeaderParseError,
    InvalidOperationError,
    MaxTreeDepthExceeded,
};

pub const FreqMap = std.AutoHashMap(u8, u32);

pub const Node = union(enum) {
    leafNode: LeafNode,
    nonLeafNode: NonLeafNode,

    pub const LeafNode = struct {
        freq: u32,
        charValue: u8,
        encoding: []const u8 = undefined,
        pub fn printInfo(leafNode: LeafNode) void {
            const charSlice = &[_]u8{leafNode.charValue};
            const charDescription = switch (leafNode.charValue) {
                '\n' => "newLine",
                '\t' => "tab",
                '\r' => "carriage return",
                else => charSlice,
            };

            print("LeafNode: char: {s}, freq: {d}, encoding: {s}\n", .{
                charDescription,
                leafNode.freq,
                leafNode.encoding,
            });
        }
    };

    pub const NonLeafNode = struct {
        freq: u32,
        left: *Node,
        right: *Node,
        pub fn printInfo(nonLeafNode: NonLeafNode) void {
            print("NonleafNode: freq: {d}\n", .{
                nonLeafNode.freq,
            });
        }
    };

    pub fn printInfo(node: Node) void {
        switch (node) {
            inline else => |n| n.printInfo(),
        }
    }

    pub fn getFreq(node: Node) u32 {
        switch (node) {
            .leafNode => {
                return node.leafNode.freq;
            },
            .nonLeafNode => {
                return node.nonLeafNode.freq;
            },
        }
    }

    pub fn isLeaf(node: Node) bool {
        switch (node) {
            .leafNode => {
                return true;
            },
            .nonLeafNode => {
                return false;
            },
        }
    }

    pub fn printSubtree(node: Node) void {
        printSubtreeWithLevel(node, 0);
    }

    fn printSubtreeWithLevel(node: Node, level: i32) void {
        switch (node) {
            .leafNode => {
                print("Level: {d}\n", .{level});
                node.leafNode.printInfo();
            },
            .nonLeafNode => {
                print("Level: {d}\n", .{level});
                node.nonLeafNode.printInfo();
                printSubtreeWithLevel(node.nonLeafNode.left.*, level + 1);
                printSubtreeWithLevel(node.nonLeafNode.right.*, level + 1);
            },
        }
    }
};

fn compare(context: void, a: *Node, b: *Node) std.math.Order {
    _ = context;
    var a_freq: u32 = undefined;
    var b_freq: u32 = undefined;
    switch (a.*) {
        .leafNode => a_freq = a.leafNode.freq,
        .nonLeafNode => a_freq = a.nonLeafNode.freq,
    }
    switch (b.*) {
        .leafNode => b_freq = b.leafNode.freq,
        .nonLeafNode => b_freq = b.nonLeafNode.freq,
    }
    return std.math.order(a_freq, b_freq);
}

//maintains a priority queue that contains pointers to nodes allocated/managed outside the Heap
//users call pq functions directly through pq
//nodes is a slice of nodes whose lifecycle is managed outside Heap.
pub const Heap = struct {
    pq: std.PriorityQueue(*Node, void, compare),
    allocator: mem.Allocator,
    pub fn init(allocator: mem.Allocator, frequencyMap: *FreqMap, nodes: []Node) !Heap {
        var pq = std.PriorityQueue(*Node, void, compare).init(allocator, {});
        var it = frequencyMap.iterator();
        var idx: usize = 0;
        while (it.next()) |entry| : (idx += 1) {
            nodes[idx] = Node{ .leafNode = .{ .charValue = entry.key_ptr.*, .freq = entry.value_ptr.* } };
            try pq.add(&nodes[idx]); //we write the address of the array elemment, array is what survives!
        }
        return Heap{
            .pq = pq,
            .allocator = allocator,
        };
    }
    pub fn deinit(self: Heap) void {
        self.pq.deinit();
    }
};

fn printMap(map: *std.AutoHashMap(u8, []const u8)) void {
    var it = map.iterator();
    while (it.next()) |entry| {
        print("key: {c} value: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
}
pub const HuffmanTree = struct {
    root: *Node,
    nodes: []Node, //we'll manage both leaf and non-leaf nodes' lifecycle inside huffmantree
    allocator: mem.Allocator,
    encodingMap: std.AutoHashMap(u8, []const u8),
    const MAX_TREE_DEPTH: usize = 64;
    const ENCODING_ARRAY_SENTINEL: u8 = 'X';
    //build the huffman tree from heap
    //if heap has 1 element, create a leafnode and we're done
    //else:
    //while heap doesnt have only 1 node remaining, do:
    //  pop 2 item from heap and connect them under non-leaf node whose freq is sum of its children
    //  add the new non-leaf node back to heap
    //end
    //
    pub fn init(allocator: mem.Allocator, freqMap: *FreqMap) !HuffmanTree {
        //every occurrence in freqmap will be leafnode first, so n
        //there will be n-1 non-leaf nodes. total sum = 2n - 1
        const nodesSize = freqMap.count() * 2 - 1;
        var nodes = try allocator.alloc(Node, nodesSize);
        var heap = try Heap.init(allocator, freqMap, nodes);
        //special case: node size is 1. then the only(root) node is a leaf node
        //todo: maybe don't compress the file if it's 1 byte long?
        if (nodesSize == 1) {
            const node = heap.pq.remove();
            nodes[0] = Node{
                .leafNode = .{
                    .charValue = node.leafNode.charValue, //for sure it's leaf
                    .freq = node.leafNode.freq,
                },
            };
            const ht = HuffmanTree{
                .nodes = nodes,
                .root = &nodes[0],
                .allocator = allocator,
                .encodingMap = try getOwnedEncodingMap(allocator, &nodes[0]),
            };
            return ht;
        } else {
            var idx = heap.pq.count(); //we start at heap's count because new nodes will be assigned to new indices
            while (heap.pq.count() > 1) : (idx += 1) {
                const n1 = heap.pq.remove();
                const n2 = heap.pq.remove();
                const newNode: Node = Node{
                    .nonLeafNode = .{
                        .freq = n1.getFreq() + n2.getFreq(),
                        .left = n1,
                        .right = n2,
                    },
                };
                nodes[idx] = newNode;
                try heap.pq.add(&nodes[idx]);
            }

            const root = heap.pq.remove();
            const ht = HuffmanTree{
                .nodes = nodes,
                .root = root,
                .allocator = allocator,
                .encodingMap = try getOwnedEncodingMap(allocator, root),
            };
            heap.deinit();
            return ht;
        }
    }
    pub fn deinit(self: *HuffmanTree) void {
        for (self.nodes) |node| {
            switch (node) {
                .leafNode => {
                    self.allocator.free(node.leafNode.encoding);
                },
                else => {},
            }
        }
        self.encodingMap.deinit();
        self.allocator.free(self.nodes);
    }

    //For compression,  we need a map: from bytes -> encoding . With it we can encode each byte to bits
    //  byte -> freqmap lookup -> freq to encoding (this is what we call encodingMap)
    //TODO: hmm do we need to pack the prefixtree(encodings) to bit strings?Not sure:
    //"translate the prefixes into bit strings and pack them into bytes to achieve the compression"
    //so: grab 8 bits from the pool?write it as char and continue?some encodings will straddle char boundries

    //map is byte -> encoding
    //todo change name, rmeove "get": getSomething() methods shouldn't have side effects
    pub fn getOwnedEncodingMap(allocator: mem.Allocator, root: *Node) !std.AutoHashMap(u8, []const u8) {
        var encodingMap = std.AutoHashMap(u8, []const u8).init(allocator);
        switch (root.*) {
            .leafNode => {
                try buildEncodingInternal(allocator, &encodingMap, root, "0");
            },
            .nonLeafNode => {
                try buildEncodingInternal(allocator, &encodingMap, root.nonLeafNode.left, "0");
                try buildEncodingInternal(allocator, &encodingMap, root.nonLeafNode.right, "1");
            },
        }
        return encodingMap;
    }
    fn buildEncodingInternal(allocator: mem.Allocator, encodingMap: *std.AutoHashMap(u8, []const u8), node: *Node, encoding: []const u8) !void {
        switch (node.*) {
            .leafNode => {
                var encodingList = std.ArrayList(u8).init(allocator);
                defer encodingList.deinit();
                for (encoding) |ch| {
                    if (ch == ENCODING_ARRAY_SENTINEL) {
                        break;
                    }
                    try encodingList.append(ch);
                }
                const encodingSlice = try encodingList.toOwnedSlice();
                node.leafNode.encoding = encodingSlice; //created final encoding slice's lifetime is managed by the huffmantree (freed in HuffmanTree.deinit())
                try encodingMap.put(node.leafNode.charValue, encodingSlice);
            },
            .nonLeafNode => {
                //avoiding heap allocation
                var addZero: [MAX_TREE_DEPTH]u8 = undefined;
                @memset(&addZero, ENCODING_ARRAY_SENTINEL);
                var addOne: [MAX_TREE_DEPTH]u8 = undefined;
                @memset(&addOne, ENCODING_ARRAY_SENTINEL);

                if (encoding.len + 1 >= MAX_TREE_DEPTH) {
                    return HuffmanError.MaxTreeDepthExceeded;
                }

                mem.copyForwards(u8, addZero[0..encoding.len], encoding);
                addZero[encoding.len] = '0';

                mem.copyForwards(u8, addOne[0..encoding.len], encoding);
                addOne[encoding.len] = '1';

                try buildEncodingInternal(allocator, encodingMap, node.nonLeafNode.left, addZero[0 .. encoding.len + 1]);
                try buildEncodingInternal(allocator, encodingMap, node.nonLeafNode.right, addOne[0 .. encoding.len + 1]);
            },
        }
    }
};

test "nodetest" {
    const leafNode = Node{ .leafNode = .{ .freq = 0, .charValue = 'a' } };
    const nonLeafNode = Node{ .nonLeafNode = .{ .freq = 0, .left = undefined, .right = undefined } };

    leafNode.printInfo();
    nonLeafNode.printInfo();

    try std.testing.expect(leafNode.isLeaf());
    try std.testing.expect(!nonLeafNode.isLeaf());
}

test "heaptest" {
    const allocator = std.testing.allocator;
    var freqMap = std.AutoHashMap(u8, u32).init(allocator);
    defer freqMap.deinit();
    try freqMap.put('A', 69);
    try freqMap.put('B', 10);
    try freqMap.put('C', 9);
    try freqMap.put('D', 8);

    const nodes = try allocator.alloc(Node, freqMap.count());
    defer allocator.free(nodes);

    var heap = try Heap.init(allocator, &freqMap, nodes);
    defer heap.deinit();

    try std.testing.expectEqual(8, heap.pq.remove().leafNode.freq);
    try std.testing.expectEqual(9, heap.pq.remove().leafNode.freq);
    try std.testing.expectEqual(10, heap.pq.remove().leafNode.freq);
    try std.testing.expectEqual(69, heap.pq.remove().leafNode.freq);
}
