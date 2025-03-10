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
};

pub const FreqMap = std.AutoHashMap(u8, u32);

pub const Node = union(enum) {
    leafNode: LeafNode,
    nonLeafNode: NonLeafNode,

    pub const LeafNode = struct {
        freq: u32,
        charValue: u8,
        pub fn printInfo(leafNode: LeafNode) void {
            const charSlice = &[_]u8{leafNode.charValue};
            const charDescription = switch (leafNode.charValue) {
                '\n' => "newLine",
                '\t' => "tab",
                '\r' => "carriage return",
                else => charSlice,
            };
            print("LeafNode: char: {s}, freq: {d}\n", .{
                charDescription,
                leafNode.freq,
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

//maintains a priority queue that contains pointers to nodes allocated in the nodes array
//users call pq functions directly through pq
pub const Heap = struct {
    pq: std.PriorityQueue(*Node, void, compare),
    nodes: []Node,
    allocator: mem.Allocator,
    pub fn init(allocator: mem.Allocator, frequencyMap: *std.AutoHashMap(u8, u32)) !Heap {
        var pq = std.PriorityQueue(*Node, void, compare).init(allocator, {});
        var nodes = try allocator.alloc(Node, frequencyMap.count());
        var it = frequencyMap.iterator();
        var idx: usize = 0;
        while (it.next()) |entry| : (idx += 1) {
            nodes[idx] = Node{ .leafNode = .{ .charValue = entry.key_ptr.*, .freq = entry.value_ptr.* } };
            try pq.add(&nodes[idx]); //we write the address of the array elemment, array is what survives!
        }
        return Heap{
            .pq = pq,
            .allocator = allocator,
            .nodes = nodes,
        };
    }
    pub fn deinit(self: Heap) void {
        self.pq.deinit();
        self.allocator.free(self.nodes);
    }
};

pub const HuffmanTree = struct {
    root: *Node,
    nodes: []Node,
    allocator: mem.Allocator,

    //build the huffman tree from heap
    //if heap has 1 element, create a leafnode and we're done
    //else:
    //while heap doesnt have only 1 node remaining, do:
    //  pop 2 item from heap and connect them under non-leaf node whose freq is sum of its children
    //  add the new non-leaf node back to heap
    //end
    //
    pub fn init(allocator: mem.Allocator, heap: *Heap) !HuffmanTree {
        const initialHeapSize = heap.pq.count();
        if (initialHeapSize == 0) {
            return HuffmanError.EmptyHeap; //shouldn't happen actually
        }
        var nodesSize: usize = initialHeapSize - 1;
        if (nodesSize == 0) {
            nodesSize = 1;
        }
        var nodes = try allocator.alloc(Node, nodesSize);
        if (nodesSize == 1) {
            const node = heap.pq.remove();
            nodes[0] = Node{
                .leafNode = .{
                    .charValue = node.leafNode.charValue, //for sure it's leaf
                    .freq = node.leafNode.freq,
                },
            };
            return HuffmanTree{
                .nodes = nodes,
                .root = &nodes[0],
                .allocator = allocator,
            };
        } else {
            var idx: usize = 0;
            while (heap.pq.count() > 1) : (idx += 1) {
                const n1 = heap.pq.remove();
                const n2 = heap.pq.remove();
                const newNode: Node = Node{ .nonLeafNode = .{
                    .freq = n1.getFreq() + n2.getFreq(),
                    .left = n1,
                    .right = n2,
                } };
                nodes[idx] = newNode;
                try heap.pq.add(&nodes[idx]); //only nodes array survives, program stack is gg after function call
            }
            return HuffmanTree{
                .nodes = nodes,
                .root = heap.pq.removeOrNull().?, //we already checked
                .allocator = allocator,
            };
        }
    }
    pub fn deinit(self: HuffmanTree) void {
        self.allocator.free(self.nodes);
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

    var heap = try Heap.init(allocator, &freqMap);
    defer heap.deinit();

    try std.testing.expectEqual(8, heap.pq.remove().leafNode.freq);
    try std.testing.expectEqual(9, heap.pq.remove().leafNode.freq);
    try std.testing.expectEqual(10, heap.pq.remove().leafNode.freq);
    try std.testing.expectEqual(69, heap.pq.remove().leafNode.freq);
}
