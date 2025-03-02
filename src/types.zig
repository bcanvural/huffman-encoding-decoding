const std = @import("std");
const print = std.debug.print;

pub const Node = union(enum) {
    leafNode: LeafNode,
    nonLeafNode: NonLeafNode,

    pub const LeafNode = struct {
        freq: u32,
        charValue: u8,
        pub fn printInfo(leafNode: LeafNode) void {
            const charSlice = &[_]u8{leafNode.charValue};
            print("LeafNode: char: {s}, freq: {d}\n", .{
                charSlice,
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
};

fn compare(context: void, a: *Node, b: *Node) std.math.Order {
    _ = context;
    var a_freq: u32 = undefined;
    var b_freq: u32 = undefined;
    if (a.isLeaf()) {
        a_freq = a.leafNode.freq;
    } else {
        a_freq = a.nonLeafNode.freq;
    }
    if (b.isLeaf()) {
        b_freq = b.leafNode.freq;
    } else {
        b_freq = b.nonLeafNode.freq;
    }
    return std.math.order(a_freq, b_freq);
}

pub const Heap = std.PriorityQueue(*Node, void, compare);

test "nodetest" {
    const leafNode = Node{ .leafNode = .{ .freq = 0, .charValue = 'a' } };
    const nonLeafNode = Node{ .nonLeafNode = .{ .freq = 0, .left = undefined, .right = undefined } };

    leafNode.printInfo();
    nonLeafNode.printInfo();

    try std.testing.expect(leafNode.isLeaf());
    try std.testing.expect(!nonLeafNode.isLeaf());
}

test "heaptest" {
    var heap = Heap.init(std.testing.allocator, {});
    defer heap.deinit();

    const values = [_]u32{ 69, 10, 9, 8 };
    var nodes: [values.len]Node = undefined;
    for (0..values.len) |idx| {
        nodes[idx] = Node{ .leafNode = .{ .freq = values[idx], .charValue = 'a' } };
        try heap.add(&nodes[idx]);
    }

    try std.testing.expectEqual(8, heap.remove().leafNode.freq);
    try std.testing.expectEqual(9, heap.remove().leafNode.freq);
    try std.testing.expectEqual(10, heap.remove().leafNode.freq);
    try std.testing.expectEqual(69, heap.remove().leafNode.freq);
}
