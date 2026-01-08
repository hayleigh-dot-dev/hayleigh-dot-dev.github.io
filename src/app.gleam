// IMPORTS ---------------------------------------------------------------------

import app/data/note
import app/data/vault
import app/meta/rss
import app/meta/sitemap
import app/serve/http
import app/serve/watcher
import app/tailwind
import app/view/document
import argv
import booklet
import filepath
import gleam/dict
import gleam/erlang/process
import gleam/io
import gleam/json
import gleam/list
import gleam/otp/static_supervisor
import gleam/result
import group_registry
import lustre/element
import simplifile

// MAIN ------------------------------------------------------------------------

pub fn main() {
  case argv.load().arguments {
    ["new", slug] -> {
      let assert Ok(_) = note.new(slug, "")

      Nil
    }

    ["build"] -> {
      let out = "dist"
      let assert Ok(vault) = vault.load()

      let _ = simplifile.create_directory("dist")
      let assert Ok(_) = {
        let slug = "/all"
        let #(meta, body) = vault.view(vault, slug)
        let html =
          document.view(meta, [], [
            body,
          ])

        let path = filepath.join(out, slug <> ".html")
        let _ = simplifile.create_directory_all(filepath.directory_name(path))

        simplifile.write(path, element.to_document_string(html))
      }

      let assert Ok(_) =
        list.try_each(dict.keys(vault.notes), fn(slug) {
          let #(meta, body) = vault.view(vault, slug)
          let html =
            document.view(meta, [], [
              body,
            ])

          let path = filepath.join(out, slug <> ".html")
          let _ = simplifile.create_directory_all(filepath.directory_name(path))

          simplifile.write(path, element.to_document_string(html))
        })

      let assert Ok(_) =
        list.try_each(dict.keys(vault.tags), fn(tag) {
          let slug = "/tag/" <> tag
          let #(meta, body) = vault.view(vault, slug)
          let html =
            document.view(meta, [], [
              body,
            ])

          let path = filepath.join(out, slug <> ".html")
          let _ = simplifile.create_directory_all(filepath.directory_name(path))

          simplifile.write(path, element.to_document_string(html))
        })

      let graph_data = vault.to_graph_json(vault)
      let assert Ok(_) =
        simplifile.write(
          filepath.join(out, "graph-data.json"),
          json.to_string(graph_data),
        )

      let css = tailwind.run("src/app.css")
      let assert Ok(_) = simplifile.write(filepath.join(out, "app.css"), css)

      let rss = rss.from_vault(vault)
      let assert Ok(_) = simplifile.write(filepath.join(out, "rss.xml"), rss)

      let sitemap = sitemap.from_vault(vault)
      let assert Ok(_) =
        simplifile.write(filepath.join(out, "sitemap.xml"), sitemap)

      let assert Ok(_) =
        simplifile.write(filepath.join(out, "CNAME"), "hayleigh.dev\n")

      let assert Ok(_) = simplifile.copy_directory("assets", out)

      Nil
    }

    ["serve"] -> {
      let assert Ok(vault) = vault.load() |> result.map(booklet.new)
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
