contract PatriciaTree {
    // List of all keys, not necessarily sorted.
    bytes[] keys;
    // Mapping of hash of key to value
    mapping (bytes32 => bytes) values;

    struct Label {
        bytes32 data;
        uint length;
    }
    struct Edge {
        bytes32 node;
        Label label;
    }
    struct Node {
        Edge[2] children;
    }
    // Particia tree nodes (hash to decoded contents)
    mapping (bytes32 => Node) nodes;
    // The current root hash, keccak256(node(path_M('')), path_M(''))
    bytes32 public root;
    Edge rootEdge;
    
    function edgeHash(Edge e) internal returns (bytes32) {
        return keccak256(e.node, e.label.length, e.label.data);
    }
    
    // Returns the hash of the encoding of a node.
    function hash(Node memory n) internal returns (bytes32) {
        // if (n.isLeaf)
        //     return keccak256(n.value);
        // else
            return keccak256(edgeHash(n.children[0]), edgeHash(n.children[1]));
    }
    
    // Returns the Merkle-proof for the given key
    // Proof format should be:
    //  - uint8 branchMask - bitmask with high bits at the positions in the key
    //                    where we have branch nodes (bit in key denotes direction)
    //  - bytes32[] hashes - hashes of sibling edges
    function getProof(bytes key) returns (uint8 branchMask, bytes32[] _siblings) {
        Label memory k = Label(keccak256(key), 256);
        Edge memory e = rootEdge;
        bytes32[256] siblings;
        uint length;
        uint numSiblings;
        while (k.length > 0) {
            var (prefix, suffix) = splitCommonPrefix(e.label, k);
            require(prefix.length == e.label.length);
            length += prefix.length + 1;
            branchMask |= 1 << (32 - length);
            var (head, tail) = chopFirstBit(suffix);
            siblings[numSiblings++] = edgeHash(nodes[e.node].children[1 - head]);
            e = nodes[e.node].children[head];
            k = tail;
        }
        _siblings = new bytes32[](numSiblings);
        for (uint i = 0; i < numSiblings; i++)
            _siblings[i] = siblings[i];
    }

    function verifyProof(bytes32 rootHash, bytes key, bytes value, uint8 branchMask, bytes32[] siblings) {
        Label memory k = Label(keccak256(key), 256);
        Edge memory e;
        e.node = keccak256(value);
        uint previousBranch = 32;
        for (uint i = 0; ; i++) {
            uint branch = lowestBitSet(branchMask);
            (k, e.label) = splitAt(k, branch);
            if (branchMask == 0)
                break;
            uint bit = bitSet(uint8(branch), k.length);
            bytes32[2] memory edgeHashes;
            edgeHashes[bit] = edgeHash(e);
            edgeHashes[1 - bit] = siblings[siblings.length - i - 1];
            e.node = keccak256(edgeHashes);
            branchMask &= uint8(~(uint(1) << branch));
            // TODO try to get rid of this
            previousBranch = branch;
        }
        require(rootHash == edgeHash(e));
    }
    
    function insert(bytes key, bytes value) {
        Label memory k = Label(keccak256(key), 256);
        values[k.data] = value;
        keys.push(key);
        rootEdge = insertAtEdge(rootEdge, k, value);
        root = edgeHash(rootEdge);
    }
    
    // TODO also return the proof (which is basically just the array of encodings of nodes)
    function insertAtNode(bytes32 nodeHash, Label key, bytes value) internal returns (bytes32) {
        Node memory n = nodes[nodeHash];
        var (head, tail) = chopFirstBit(key);
        n.children[head] = insertAtEdge(n.children[head], tail, value);
        return replaceNode(nodeHash, n);
    }
    
    function insertAtEdge(Edge e, Label key, bytes value) internal returns (Edge) {
        var (prefix, suffix) = splitCommonPrefix(e.label, key);
        bytes32 newNodeHash;
        if (prefix.length >= e.label.length) {
            newNodeHash = insertAtNode(e.node, suffix, value);
        } else {
            // Mismatch, so let us create a new branch node.
            var (head, tail) = chopFirstBit(suffix);
            Node memory branchNode;
            branchNode.children[head] = Edge(insertValueNode(value), tail);
            branchNode.children[1 - head] = Edge(e.node, removePrefix(e.label, prefix.length + 1));
            newNodeHash = insertNode(branchNode);
        }
        return Edge(newNodeHash, prefix);
    }
    function splitCommonPrefix(Label check, Label label) internal returns (Label prefix, Label labelSuffix) {
        return splitAt(label, commonPrefix(check, label));
    }
    /// Splits the label at the given position and returns prefix and suffix,
    /// i.e. prefix.length == pos and prefix.data . suffix.data == l.data.
    function splitAt(Label l, uint pos) internal returns (Label prefix, Label suffix) {
        require(pos <= l.length);
        prefix.length = pos;
        prefix.data = (l.data >> (32 - pos)) << (32 - pos);
        suffix.length = l.length - pos;
        suffix.data = l.data << pos;
    }
    function commonPrefix(Label a, Label b) internal returns (uint prefix) {
        for (prefix = 0; prefix < a.length && prefix < b.length; prefix++)
            if (a.data[prefix] != b.data[prefix])
                break;
    }
    function removePrefix(Label l, uint prefix) internal returns (Label r) {
        require(prefix <= l.length);
        r.length = l.length - prefix;
        l.data = l.data << prefix;
    }
    function chopFirstBit(Label l) internal returns (uint firstBit, Label tail) {
        require(l.length > 0);
        return (uint(l.data >> 255), Label(l.data << 1, l.length - 1));
    }
    function insertValueNode(bytes value) internal returns (bytes32 newHash) {
        // Node memory n;
        // n.isLeaf = true;
        // n.value = value;
        // return insertNode(n);
    }
    function insertNode(Node memory n) internal returns (bytes32 newHash) {
        bytes32 h = hash(n);
        nodes[h] = n;
        return h;
    }
    function replaceNode(bytes32 oldHash, Node memory n) internal returns (bytes32 newHash) {
        delete nodes[oldHash];
        return insertNode(n);
    }
    function lowestBitSet(uint8 bitfield) returns (uint bit) {
        for (bit = 31; bit > 0; bit --)
            if (bitSet(bitfield, bit) != 0)
                return bit;
        return 0;
    }
    function bitSet(uint8 bitfield, uint bit) returns (uint) {
        return bitfield & (1 << (31-bit)) != 0 ? 1 : 0;
    }
}