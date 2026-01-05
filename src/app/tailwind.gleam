// IMPORTS ---------------------------------------------------------------------

import gleam/regexp
import gleam/string
import gleam_community/ansi
import tailwind

//

pub fn run(input: String) -> String {
  let assert Ok(re) = regexp.from_string("Done in .+")
  let assert Ok(stdout) = tailwind.install_and_run(["--input=" <> input])

  stdout
  |> ansi.strip
  |> string.replace("≈ tailwindcss v4.1.18\n\n", "")
  |> regexp.replace(re, _, "")
}
