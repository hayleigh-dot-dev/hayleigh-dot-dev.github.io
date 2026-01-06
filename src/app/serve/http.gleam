import app/note
import app/serve/middleware
import app/serve/reload
import app/serve/watcher.{type Change}
import app/vault.{type Vault}
import app/view/document
import booklet.{type Booklet}
import ewe.{type Request, type Response}
import filepath
import gleam/dict
import gleam/erlang/process.{type Name}
import gleam/http/request.{Request}
import gleam/http/response
import gleam/result
import group_registry.{type Message}
import lustre/attribute
import lustre/element
import lustre/element/html

//

pub fn supervised(
  vault: Booklet(Vault),
  css: Booklet(String),
  group_name: Name(Message(Change)),
) {
  ewe.new(handler(_, vault, css, group_name))
  |> ewe.listening(1234)
  |> ewe.supervised
}

fn handler(
  request: Request,
  vault: Booklet(Vault),
  css: Booklet(String),
  group_name: Name(Message(Change)),
) -> Response {
  use <- middleware.redirect_root(request)
  use request <- middleware.add_html_extensions(request)
  use <- middleware.serve_static_assets(request)

  case request.path {
    "/.live" <> path ->
      reload.start(Request(..request, path:), vault, css, group_name)

    "/app.css" ->
      response.new(200)
      |> response.set_header("content-type", "text/css")
      |> response.set_body(ewe.TextData(booklet.get(css)))

    path ->
      serve_note(vault, filepath.strip_extension(path))
      |> result.lazy_or(fn() { serve_note(vault, "/404") })
      |> result.lazy_unwrap(fn() {
        response.set_body(response.new(404), ewe.Empty)
      })
  }
}

fn serve_note(vault: Booklet(Vault), slug: String) -> Result(Response, Nil) {
  let vault = booklet.get(vault)
  use note <- result.try(dict.get(vault.notes, slug))

  let html =
    document.view(
      note.document_meta(note),
      [html.script([attribute.src("/live-reload.js")], "")],
      [
        html.div([attribute.class("p-4 mx-auto max-w-3xl")], [
          note.view(note, vault.references(vault, to: note.meta.slug)),
        ]),
      ],
    )

  let body = element.to_document_string(html)

  response.new(200)
  |> response.set_header("content-type", "text/html")
  |> response.set_body(ewe.TextData(body))
  |> Ok
}
