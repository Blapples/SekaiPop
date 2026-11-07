// Checks a QML file for the mistakes that stop Quickshell from loading it and that plain node can see:
//   - the same `id:` twice in one scope (a `Component { }` block is its own scope)
//   - the same member twice at the top level of the root object (4-space indent): a property, a function, a
//     signal, or a handler such as `Component.onCompleted` or `onWidthChanged` ("Property value set multiple times")
//   - braces and brackets that do not balance
// Used by tests/watertank-test. Returns a list of problems (empty = fine).
function strip(text) {
    return text.replace(/"(\\.|[^"\\\n])*"/g, '""').replace(/'(\\.|[^'\\\n])*'/g, "''").replace(/\/\/[^\n]*/g, "")
}

// Removes every `Component { ... }` block (by matching braces), returning [textWithout, blocks[]].
function splitComponents(t) {
    const blocks = []
    let out = "", i = 0
    const re = /\bComponent\s*\{/g
    let m
    while ((m = re.exec(t)) !== null) {
        const start = m.index
        let depth = 0, j = m.index + m[0].length - 1
        for (; j < t.length; j++) {
            if (t[j] === "{") depth++
            else if (t[j] === "}") { depth--; if (depth === 0) break }
        }
        out += t.slice(i, start)
        blocks.push(t.slice(start + m[0].length, j))
        i = j + 1
        re.lastIndex = i
    }
    out += t.slice(i)
    return [out, blocks]
}

function dups(list) {
    const seen = {}, bad = []
    for (const k of list) { seen[k] = (seen[k] || 0) + 1 }
    for (const k in seen) if (seen[k] > 1) bad.push(k + " x" + seen[k])
    return bad
}

function scope(t, label, problems) {
    const ids = [...t.matchAll(/\bid:\s*([A-Za-z_]\w*)/g)].map(m => m[1])
    for (const d of dups(ids)) problems.push(label + ": id " + d)
}

module.exports = function check(text, name) {
    const problems = []
    const t = strip(text)
    for (const [o, c] of [["{", "}"], ["(", ")"], ["[", "]"]])
        if (t.split(o).length !== t.split(c).length) problems.push(name + ": unbalanced " + o + c)
    const [main, blocks] = splitComponents(t)
    scope(main, name, problems)
    blocks.forEach((b, i) => {
        // a Component inside a Component is checked as part of its parent's block here
        scope(splitComponents(b)[0], name + " (Component #" + (i + 1) + ")", problems)
    })
    const top = []
    for (const m of main.matchAll(/^ {4}(?:readonly property|required property|property|function|signal)\s+(?:[\w.<>]+\s+)?([A-Za-z_]\w*)/gm)) top.push(m[1])
    for (const m of main.matchAll(/^ {4}(Component\.on\w+|on[A-Z]\w*)\s*[:(]/gm)) top.push(m[1])
    for (const d of dups(top)) problems.push(name + ": member " + d)
    return problems
}
