// IMPORTS ---------------------------------------------------------------------

import app/vault.{type Vault}
import booklet.{type Booklet}
import filepath
import gleam/erlang/process.{type Name}
import gleam/list
import gleam/otp/supervision.{type ChildSpecification}
import gleam/regexp
import gleam/result
import gleam/string
import group_registry
import polly.{type Watcher}
import tailwind

// TYPES -----------------------------------------------------------------------

pub type Change {
  Note
  Styles
}

//

///
///
pub fn supervised(
  vault: Booklet(Vault),
  css: Booklet(String),
  group: Name(group_registry.Message(Change)),
) -> ChildSpecification(Watcher) {
  polly.new()
  |> polly.add_dir("notes")
  |> polly.add_file("src/app.css")
  |> polly.interval(100)
  |> polly.add_callback(fn(event) {
    let channel = group_registry.get_registry(group)

    case event {
      polly.Created(path: "notes" <> slug) -> {
        let slug = filepath.strip_extension(slug)
        let _ =
          booklet.update(vault, fn(vault) {
            vault.add(vault, slug) |> result.unwrap(vault)
          })

        Nil
      }

      polly.Changed(path: "src/app.css") -> {
        let assert Ok(re) = regexp.from_string("Done in .+")
        let assert Ok(stdout) = tailwind.run(["--input=src/app.css"])

        stdout
        |> string.replace("≈ tailwindcss v4.1.18\n\n", "")
        |> regexp.replace(re, _, "")
        |> booklet.set(css, _)

        list.each(group_registry.members(channel, "*"), process.send(_, Styles))
      }

      polly.Changed(path: "notes" <> slug as path) -> {
        let slug = filepath.strip_extension(slug)
        let _ =
          booklet.update(vault, fn(vault) {
            vault.remove(vault, slug)
            |> vault.add(path)
            |> result.unwrap(vault)
          })

        list.each(group_registry.members(channel, slug), process.send(_, Note))
      }

      polly.Deleted(path: "notes" <> slug) -> {
        let slug = filepath.strip_extension(slug)
        let _ = booklet.update(vault, vault.remove(_, slug))

        Nil
      }

      _ -> Nil
    }
  })
  |> polly.supervised
}
