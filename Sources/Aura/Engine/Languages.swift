import Foundation

/// File extension → programming language, with icons from the open-source vscord project.
enum Languages {
    struct Language: Sendable {
        var name: String
        var icon: String

        var iconURL: String { "https://raw.githubusercontent.com/leonardssh/vscord/main/assets/icons/\(icon).png" }
    }

    private static let byExtension: [String: Language] = {
        let table: [(String, String, [String])] = [
            ("Swift", "swift", ["swift"]), ("TypeScript", "ts", ["ts", "mts", "cts"]), ("TSX", "tsx", ["tsx"]),
            ("JavaScript", "js", ["js", "mjs", "cjs"]), ("JSX", "jsx", ["jsx"]), ("Python", "python", ["py", "pyw"]),
            ("Rust", "rust", ["rs"]), ("Go", "go", ["go"]), ("Java", "java", ["java"]), ("Kotlin", "kotlin", ["kt", "kts"]),
            ("Ruby", "ruby", ["rb"]), ("PHP", "php", ["php"]), ("C", "c", ["c", "h"]),
            ("C++", "cpp", ["cpp", "cc", "cxx", "hpp", "hh"]), ("C#", "csharp", ["cs"]),
            ("Objective-C", "objective-c", ["m", "mm"]), ("HTML", "html", ["html", "htm"]), ("CSS", "css", ["css"]),
            ("SCSS", "scss", ["scss", "sass"]), ("Less", "less", ["less"]), ("JSON", "json", ["json", "jsonc"]),
            ("Markdown", "markdown", ["md", "markdown"]), ("MDX", "markdownx", ["mdx"]), ("YAML", "yaml", ["yml", "yaml"]),
            ("TOML", "toml", ["toml"]), ("Shell", "shell", ["sh", "zsh", "bash", "fish"]), ("SQL", "sql", ["sql"]),
            ("Vue", "vue", ["vue"]), ("Svelte", "svelte", ["svelte"]), ("Astro", "astro", ["astro"]), ("Dart", "dart", ["dart"]),
            ("Lua", "lua", ["lua"]), ("XML", "xml", ["xml", "plist"]), ("GraphQL", "graphql", ["graphql", "gql"]),
            ("Prisma", "prisma", ["prisma"]), ("Elixir", "elixir", ["ex", "exs"]), ("Haskell", "haskell", ["hs"]),
            ("Scala", "scala", ["scala"]), ("Zig", "zig", ["zig"]), ("Nim", "nim", ["nim"]), ("R", "r", ["r"]),
            ("Julia", "julia", ["jl"]), ("Jupyter", "jupyter", ["ipynb"]), ("LaTeX", "tex", ["tex"]), ("Metal", "metal", ["metal"]),
            ("SVG", "svg", ["svg"]), ("Text", "text", ["txt"]), ("Env", "env", ["env"]), ("Terraform", "terraform", ["tf"]),
            ("Gradle", "gradle", ["gradle"]), ("Perl", "perl", ["pl"]), ("Clojure", "clojure", ["clj", "cljs"]),
            ("OCaml", "ocaml", ["ml"]), ("F#", "fsharp", ["fs", "fsx"]), ("Erlang", "erlang", ["erl"]),
            ("Solidity", "solidity", ["sol"]), ("WebAssembly", "wasm", ["wasm", "wat"]), ("GLSL", "glsl", ["glsl", "vert", "frag"]),
            ("Visual Basic", "vb", ["vb"]), ("PowerShell", "powershell", ["ps1"]), ("Crystal", "crystal", ["cr"]),
            ("Gleam", "gleam", ["gleam"]), ("Odin", "odin", ["odin"]), ("Mojo", "mojo", ["mojo"]), ("Typst", "typst", ["typ"]),
        ]
        var map: [String: Language] = [:]
        for (name, icon, exts) in table { for e in exts { map[e] = Language(name: name, icon: icon) } }
        return map
    }()

    private static let byFileName: [String: Language] = [
        "dockerfile": Language(name: "Docker", icon: "docker"), "makefile": Language(name: "Makefile", icon: "makefile"),
        "package.json": Language(name: "npm", icon: "npm"), "cargo.toml": Language(name: "Cargo", icon: "cargo"),
        "gemfile": Language(name: "Gemfile", icon: "gemfile"), ".gitignore": Language(name: "Git", icon: "git"),
        "tailwind.config.js": Language(name: "Tailwind", icon: "tailwind"), "vite.config.ts": Language(name: "Vite", icon: "viteconfig"),
        "package.swift": Language(name: "Swift", icon: "swift"),
    ]

    static func language(forFile file: String) -> Language? {
        let lower = file.lowercased()
        if let l = byFileName[lower] { return l }
        return byExtension[(lower as NSString).pathExtension]
    }
}
