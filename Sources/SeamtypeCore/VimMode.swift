/// Follows vim's keys from normal mode until one starts insert mode, so that in an app set to
/// "Esc: Vim" Seamtype passes normal-mode commands (`dd`, `ciw`, `:wq`) straight through instead
/// of holding them as a word, and starts deciding words again once the user is typing text.
///
/// It reads only what vim itself would: counts, registers, operators with their motions and
/// text objects (`diw` is a delete, `ciw` starts inserting), keys that take a character (`fa`,
/// `ri`), visual mode and the `:`/`/` command line. Quitting (`:wq⏎`, `ZZ`) also ends it, so the
/// shell the user comes back to isn't passed through. Mappings that enter insert mode can't be
/// seen; Esc puts it back in normal mode.
public struct VimNormalMode: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case normal
        /// The next key is a character argument (`f`, `t`, `r`, `m`, `"`, `q`, `@`, `'`, `z`…).
        case argument(then: After)
        /// After `g`: `gi`/`gI` insert, `gu`/`gU`/`g~`/`g?` are operators, `gv` is visual.
        case g(visual: Bool)
        /// An operator waits for its motion; `change` inserts once the motion is done.
        case operatorPending(op: Character, change: Bool)
        case visual
        /// `:`, `/` or `?`: everything goes to vim until Return or Esc.
        case commandLine(then: After)
        /// After `Z`: `ZZ` and `ZQ` quit.
        case z
    }

    /// Where a pending key leaves vim.
    enum After: Equatable, Sendable {
        case normal, visual, insert
    }

    var state: State = .normal
    /// `q{register}` started recording a macro, so the next `q` stops it and takes no argument.
    var recording = false
    /// What's typed on the `:` command line, to see a quit.
    var command = ""

    static let quitCommands: Set<String> = ["q", "qa", "qall", "quit", "quita", "quitall", "wq", "wqa", "wqall",
                                            "x", "xa", "xall", "xit", "exi", "exit", "cq", "cquit"]

    public init() {}

    /// Feeds one printable key that vim received. Returns true when vim stops taking the keys:
    /// the key started insert mode, or quit vim.
    public mutating func feed(_ ch: Character) -> Bool {
        switch state {
        case .normal: return normal(ch)
        case .visual: return visual(ch)
        case .argument(let then): return finish(then)
        case .g(let visual): return afterG(ch, visual: visual)
        case .operatorPending(let op, let change): return motion(ch, op: op, change: change)
        case .commandLine: command.append(ch); return false
        case .z: state = .normal; return ch == "Z" || ch == "Q"
        }
    }

    /// Return: ends the command line (a `c/pattern⏎` goes on to insert, `:wq⏎` quits).
    public mutating func enter() -> Bool {
        if case .commandLine(let then) = state {
            var name = command.trimmingCharacters(in: .whitespaces)
            if name.hasSuffix("!") { name.removeLast() }
            command = ""
            if Self.quitCommands.contains(name) { state = .normal; return true }
            return finish(then)
        }
        if case .operatorPending(_, let change) = state { return finish(change ? .insert : .normal) }
        return false
    }

    /// Delete: on the command line it erases a character, and on an empty one leaves it.
    public mutating func delete() {
        guard case .commandLine = state else { return }
        if command.isEmpty { state = .normal } else { command.removeLast() }
    }

    /// Esc cancels whatever is pending and leaves visual mode.
    public mutating func escape() {
        state = .normal
        command = ""
    }

    private mutating func finish(_ after: After) -> Bool {
        switch after {
        case .normal: state = .normal
        case .visual: state = .visual
        case .insert: state = .normal; return true
        }
        return false
    }

    private mutating func normal(_ ch: Character) -> Bool {
        switch ch {
        case "i", "a", "I", "A", "o", "O", "s", "S", "C", "R": return true
        case "c": state = .operatorPending(op: ch, change: true)
        case "d", "y", "<", ">", "=", "!": state = .operatorPending(op: ch, change: false)
        case "g": state = .g(visual: false)
        case "v", "V": state = .visual
        case ":", "/", "?": state = .commandLine(then: .normal)
        case "q":
            if recording { recording = false } else { recording = true; state = .argument(then: .normal) }
        case "Z": state = .z
        case "f", "t", "F", "T", "r", "m", "\"", "@", "'", "`", "z", "[", "]":
            state = .argument(then: .normal)
        default: break // counts, motions, x, p, u, J, ., n, …
        }
        return false
    }

    private mutating func visual(_ ch: Character) -> Bool {
        switch ch {
        case "c", "s", "C", "S", "R", "I", "A": state = .normal; return true
        case "i", "a", "f", "t", "F", "T", "\"", "'", "`", "z", "[", "]": state = .argument(then: .visual)
        case "r": state = .argument(then: .normal)
        case "g": state = .g(visual: true)
        case ":": state = .commandLine(then: .normal)
        case "/", "?": state = .commandLine(then: .visual)
        case "v", "V", "d", "x", "X", "D", "y", "Y", "p", "P", "J", "u", "U", "~", "<", ">", "=", "!":
            state = .normal
        default: break
        }
        return false
    }

    private mutating func afterG(_ ch: Character, visual: Bool) -> Bool {
        switch ch {
        case "i", "I": state = .normal; return true
        case "u", "U", "~", "?", "q", "w":
            state = visual ? .normal : .operatorPending(op: ch, change: false)
        case "v": state = .visual
        default: state = visual ? .visual : .normal
        }
        return false
    }

    private mutating func motion(_ ch: Character, op: Character, change: Bool) -> Bool {
        let done: After = change ? .insert : .normal
        switch ch {
        case "1"..."9": return false // a count inside the operator (d2w)
        case "i", "a", "f", "t", "F", "T", "'", "`", "[", "]", "\"": state = .argument(then: done)
        case "g": state = .argument(then: done) // dgg, cge
        case "/", "?": state = .commandLine(then: done)
        default: return finish(done) // dd, cc, dw, c$, y}, …
        }
        return false
    }
}
