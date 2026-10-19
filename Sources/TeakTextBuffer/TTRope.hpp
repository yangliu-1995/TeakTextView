#pragma once
#include <algorithm>
#include <functional>
#include <memory>
#include <string>
#include <span>
#include <utility>
#include <cstdint>
#include <vector>

namespace teak {
constexpr size_t chunkCapacity = 8192;
struct Node;
using Tree = std::shared_ptr<const Node>;

// Leaf pieces share immutable buffers, including after split/delete/undo.
struct Node {
    Tree left, right;
    std::shared_ptr<const std::u16string> buffer;
    std::shared_ptr<const std::vector<uint16_t>> lineEnds;
    size_t start = 0, length = 0, breaks = 0, leaves = 0;
    int height = 1;
    char16_t first = 0, last = 0;
    Node(std::shared_ptr<const std::u16string> text, size_t offset, size_t count);
    Node(Tree lhs, Tree rhs);
};
inline size_t length(const Tree &t) { return t ? t->length : 0; }
inline int height(const Tree &t) { return t ? t->height : 0; }
Tree join(Tree left, Tree right);
std::pair<Tree, Tree> split(Tree tree, size_t offset);
Tree fromString(const std::u16string &text);
void visit(Tree tree, size_t offset, size_t count,
           const std::function<void(std::span<const char16_t>)> &body);
char16_t character(Tree tree, size_t offset);
size_t lineNumber(Tree tree, size_t offset);
bool isLineStart(Tree tree, size_t offset);
}
