#include "TTRope.hpp"
#include <cassert>

namespace teak {
Node::Node(std::shared_ptr<const std::u16string> text, size_t offset, size_t count)
    : buffer(std::move(text)), start(offset), length(count), leaves(1) {
    assert(count > 0 && count <= chunkCapacity);
    first = (*buffer)[start];
    last = (*buffer)[start + count - 1];
    std::vector<uint16_t> ends;
    for (size_t i = 0; i < count; ++i) {
        const auto c = (*buffer)[start + i];
        if (i && c == u'\n' && (*buffer)[start + i - 1] == u'\r') continue;
        if (c == u'\r' || c == u'\n' || c == 0x2028 || c == 0x2029)
            ends.push_back(static_cast<uint16_t>(i + 1));
    }
    breaks = ends.size();
    if (!ends.empty()) lineEnds = std::make_shared<const std::vector<uint16_t>>(std::move(ends));
}
Node::Node(Tree lhs, Tree rhs) : left(std::move(lhs)), right(std::move(rhs)) {
    length = left->length + right->length;
    breaks = left->breaks + right->breaks - (left->last == u'\r' && right->first == u'\n');
    leaves = left->leaves + right->leaves;
    height = 1 + std::max(left->height, right->height);
    first = left->first;
    last = right->last;
}
static Tree branch(Tree left, Tree right) {
    if (!left) return right;
    if (!right) return left;
    return std::make_shared<Node>(left, right);
}
static Tree balance(Tree left, Tree right) {
    if (height(left) > height(right) + 1) {
        if (height(left->left) >= height(left->right))
            return branch(left->left, branch(left->right, right));
        const auto pivot = left->right;
        return branch(branch(left->left, pivot->left), branch(pivot->right, right));
    }
    if (height(right) > height(left) + 1) {
        if (height(right->right) >= height(right->left))
            return branch(branch(left, right->left), right->right);
        const auto pivot = right->left;
        return branch(branch(left, pivot->left), branch(pivot->right, right->right));
    }
    return branch(left, right);
}
Tree join(Tree left, Tree right) {
    if (!left) return right;
    if (!right) return left;
    // Coalesce small adjacent edits: sustained typing must not add one leaf per key.
    if (left->buffer && right->buffer && left->length + right->length <= chunkCapacity) {
        auto text = std::make_shared<std::u16string>();
        text->reserve(left->length + right->length);
        text->append(*left->buffer, left->start, left->length);
        text->append(*right->buffer, right->start, right->length);
        return std::make_shared<Node>(text, 0, text->size());
    }
    if (height(left) > height(right) + 1)
        return balance(left->left, join(left->right, right));
    if (height(right) > height(left) + 1)
        return balance(join(left, right->left), right->right);
    return branch(left, right);
}
std::pair<Tree, Tree> split(Tree tree, size_t offset) {
    if (!tree || !offset) return {nullptr, tree};
    if (offset >= tree->length) return {tree, nullptr};
    if (tree->buffer) {
        return {std::make_shared<Node>(tree->buffer, tree->start, offset),
                std::make_shared<Node>(tree->buffer, tree->start + offset, tree->length - offset)};
    }
    if (offset < tree->left->length) {
        auto parts = split(tree->left, offset);
        return {parts.first, join(parts.second, tree->right)};
    }
    auto parts = split(tree->right, offset - tree->left->length);
    return {join(tree->left, parts.first), parts.second};
}
Tree fromString(const std::u16string &text) {
    Tree tree;
    for (size_t offset = 0; offset < text.size();) {
        auto count = std::min(chunkCapacity, text.size() - offset);
        // Keep surrogate pairs together for streaming encoding on save.
        if (offset + count < text.size() && text[offset + count - 1] >= 0xD800
            && text[offset + count - 1] <= 0xDBFF) --count;
        auto chunk = std::make_shared<std::u16string>(text, offset, count);
        tree = join(tree, std::make_shared<Node>(chunk, 0, count));
        offset += count;
    }
    return tree;
}
void visit(Tree tree, size_t offset, size_t count,
           const std::function<void(std::span<const char16_t>)> &body) {
    if (!tree || !count) return;
    assert(offset <= tree->length && count <= tree->length - offset);
    if (tree->buffer) {
        body(std::span(*tree->buffer).subspan(tree->start + offset, count));
        return;
    }
    const auto leftLength = tree->left->length;
    if (offset < leftLength) {
        const auto leftCount = std::min(count, leftLength - offset);
        visit(tree->left, offset, leftCount, body);
        count -= leftCount;
        offset = 0;
    } else {
        offset -= leftLength;
    }
    if (count) visit(tree->right, offset, count, body);
}
char16_t character(Tree tree, size_t offset) {
    while (!tree->buffer) {
        if (offset < tree->left->length) tree = tree->left;
        else { offset -= tree->left->length; tree = tree->right; }
    }
    return (*tree->buffer)[tree->start + offset];
}
size_t lineNumber(Tree tree, size_t offset) {
    assert(offset <= length(tree));
    const auto root = tree;
    auto remaining = offset;
    size_t breaks = 0;
    char16_t previous = 0;
    // Add whole subtrees; binary-search only the terminal leaf's newline index.
    const auto append = [&](const Tree &part, size_t count, char16_t last) {
        breaks += count;
        if (previous == u'\r' && part->first == u'\n') --breaks;
        previous = last;
    };
    while (tree && remaining) {
        if (remaining == tree->length) {
            append(tree, tree->breaks, tree->last);
            break;
        }
        if (tree->buffer) {
            const auto count = tree->lineEnds
                ? std::upper_bound(tree->lineEnds->begin(), tree->lineEnds->end(), remaining)
                    - tree->lineEnds->begin() : 0;
            append(tree, count, (*tree->buffer)[tree->start + remaining - 1]);
            break;
        }
        if (remaining < tree->left->length) tree = tree->left;
        else {
            append(tree->left, tree->left->breaks, tree->left->last);
            remaining -= tree->left->length;
            tree = tree->right;
        }
    }
    // A caret between CR and LF is still on the preceding logical line.
    if (previous == u'\r' && offset < length(root) && character(root, offset) == u'\n') --breaks;
    return breaks + 1;
}
bool isLineStart(Tree tree, size_t offset) {
    assert(offset <= length(tree));
    if (!offset) return true;
    const auto previous = character(tree, offset - 1);
    if (previous == u'\n' || previous == 0x2028 || previous == 0x2029) return true;
    return previous == u'\r' && (offset == length(tree) || character(tree, offset) != u'\n');
}
}
