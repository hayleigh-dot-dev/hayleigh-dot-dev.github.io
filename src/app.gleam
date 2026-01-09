// IMPORTS ---------------------------------------------------------------------

import app/build
import app/data/note
import app/serve
import argv
import gleam/io

// MAIN ------------------------------------------------------------------------

pub fn main() {
  case argv.load().arguments {
    ["new", slug] -> {
      let assert Ok(_) = note.new(slug, "")

      Nil
    }

    ["build"] -> build.main()

    ["serve"] -> serve.main()

    _ -> io.println("Usage: gleam run (build | serve)")
  }
}
