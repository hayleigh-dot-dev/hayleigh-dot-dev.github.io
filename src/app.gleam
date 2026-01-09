// IMPORTS ---------------------------------------------------------------------

import app/data/note
import app/data/vault
import app/meta/rss
import app/meta/sitemap
import app/serve
import app/tailwind
import app/view/document
import argv
import filepath
import gleam/dict
import gleam/io
import gleam/json
import gleam/list
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

    ["serve"] -> serve.main()

    _ -> io.println("Usage: gleam run (build | serve)")
  }
}
