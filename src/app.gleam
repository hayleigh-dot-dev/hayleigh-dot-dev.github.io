// IMPORTS ---------------------------------------------------------------------

import app/meta/rss
import app/meta/sitemap
import app/note
import app/serve/http
import app/serve/watcher
import app/tailwind
import app/vault
import app/view/document
import argv
import booklet
import filepath
import gleam/dict
import gleam/erlang/process
import gleam/io
import gleam/list
import gleam/otp/static_supervisor
import gleam/result
import group_registry
import lustre/attribute
import lustre/element
import lustre/element/html
import simplifile

// MAIN ------------------------------------------------------------------------

pub fn main() {
  case argv.load().arguments {
    ["build"] -> {
      let assert Ok(vault) = vault.new("notes")
      let out = "dist"

      let _ = simplifile.create_directory("dist")
      let assert Ok(_) =
        list.try_each(dict.values(vault.notes), fn(note) {
          let html =
            document.view(note.document_meta(note), [], [
              html.div([attribute.class("p-4 mx-auto max-w-3xl")], [
                note.view(note),
              ]),
            ])
          let path = filepath.join(out, note.meta.slug <> ".html")
          let _ = simplifile.create_directory_all(filepath.directory_name(path))

          simplifile.write(path, element.to_document_string(html))
        })

      let css = tailwind.run("src/app.css")

      let assert Ok(_) = simplifile.write(filepath.join(out, "app.css"), css)

      let rss = rss.from_vault(vault)
      let assert Ok(_) = simplifile.write(filepath.join(out, "rss.xml"), rss)

      let sitemap = sitemap.from_vault(vault)
      let assert Ok(_) =
        simplifile.write(filepath.join(out, "sitemap.xml"), sitemap)

      let assert Ok(_) =
        simplifile.write(filepath.join(out, "CNAME"), "hayleigh.dev\n")

      Nil
    }

    ["serve"] -> {
      let assert Ok(vault) = vault.new("notes") |> result.map(booklet.new)
      let css = booklet.new(tailwind.run("src/app.css"))

      let group_name = process.new_name("group")

      let group = group_registry.supervised(group_name)
      let watcher = watcher.supervised(vault, css, group_name)
      let server = http.supervised(vault, css, group_name)

      let assert Ok(_) =
        static_supervisor.new(static_supervisor.RestForOne)
        |> static_supervisor.add(group)
        |> static_supervisor.add(watcher)
        |> static_supervisor.add(server)
        |> static_supervisor.start

      process.sleep_forever()
    }

    _ -> io.println("Usage: gleam run (build | serve)")
  }
}
