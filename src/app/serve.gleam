// IMPORTS ---------------------------------------------------------------------

import app/data/note
import app/data/vault.{type Vault}
import app/tailwind
import app/view/document
import booklet.{type Booklet}
import ewe.{type Request, type Response}
import filepath
import gleam/erlang/process.{type Name}
import gleam/http/request.{Request}
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/otp/static_supervisor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result
import group_registry.{type Message}
import lustre/attribute
import lustre/element
import lustre/element/html
import polly.{type Watcher}

// MAIN ------------------------------------------------------------------------

pub fn main() {
  let assert Ok(vault) = vault.load() |> result.map(booklet.new)
  let css = booklet.new(tailwind.run("src/app.css"))
  let group = process.new_name("group")

  let assert Ok(_) =
    static_supervisor.new(static_supervisor.RestForOne)
    |> static_supervisor.add(group_registry.supervised(group))
    |> static_supervisor.add(watcher(vault, css, group))
    |> static_supervisor.add(server(vault, css, group))
    |> static_supervisor.start

  process.sleep_forever()
}

// HTTP SERVER -----------------------------------------------------------------

fn server(
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
  use <- redirect_root(request)
  use request <- add_html_extensions(request)
  use <- serve_static_assets(request)

  case request.path {
    "/.live" <> path ->
      start_live_reload(Request(..request, path:), vault, css, group_name)

    "/app.css" ->
      response.new(200)
      |> response.set_header("content-type", "text/css")
      |> response.set_body(ewe.TextData(booklet.get(css)))

    "/graph-data.json" -> serve_graph_data(vault)

    path ->
      serve_note(vault, filepath.strip_extension(path))
      |> result.lazy_or(fn() { serve_note(vault, "/404") })
      |> result.lazy_unwrap(fn() {
        response.set_body(response.new(404), ewe.Empty)
      })
  }
}

fn start_live_reload(
  request: Request,
  vault: Booklet(Vault),
  css: Booklet(String),
  group: Name(Message(Change)),
) {
  let slug = filepath.strip_extension(request.path)
  use connection, state, message <-
    ewe.upgrade_websocket(
      request,
      on_init: fn(_, selector) {
        let self = process.self()
        let channel = group_registry.get_registry(group)

        let selector =
          selector
          |> process.select(group_registry.join(channel, "*", self))
          |> process.select(group_registry.join(channel, slug, self))

        #(slug, selector)
      },
      handler: _,
      on_close: fn(_, _) {
        let self = process.self()
        let channel = group_registry.get_registry(group)

        group_registry.leave(channel, "*", [self])
        group_registry.leave(channel, slug, [self])

        Nil
      },
    )

  case message {
    ewe.Text(..) | ewe.Binary(..) -> ewe.websocket_continue(state)

    ewe.User(NoteChanged) -> {
      let vault = booklet.get(vault)
      let #(_, body) = vault.view(vault, slug)

      let assert Ok(_) =
        ewe.send_text_frame(connection, {
          json.to_string(
            json.object([
              #("type", json.string("html")),
              #("content", json.string(element.to_string(body))),
            ]),
          )
        })

      ewe.websocket_continue(state)
    }

    ewe.User(CssChanged) -> {
      let assert Ok(_) =
        ewe.send_text_frame(connection, {
          json.to_string(
            json.object([
              #("type", json.string("css")),
              #("content", json.string(booklet.get(css))),
            ]),
          )
        })

      ewe.websocket_continue(state)
    }
  }
}

fn serve_graph_data(vault: Booklet(Vault)) -> Response {
  let vault = booklet.get(vault)
  let json = vault.to_graph_json(vault)

  response.new(200)
  |> response.set_header("content-type", "application/json")
  |> response.set_body(ewe.TextData(json.to_string(json)))
}

fn serve_note(vault: Booklet(Vault), slug: String) -> Result(Response, Nil) {
  let vault = booklet.get(vault)
  let #(meta, body) = vault.view(vault, slug)

  let html =
    document.view(meta, [html.script([attribute.src("/live-reload.js")], "")], [
      body,
    ])

  let body = element.to_document_string(html)

  response.new(200)
  |> response.set_header("content-type", "text/html")
  |> response.set_body(ewe.TextData(body))
  |> Ok
}

fn redirect_root(request: Request, next: fn() -> Response) -> Response {
  case request.path {
    "/" ->
      response.new(302)
      |> response.set_header("location", "/index.html")
      |> response.set_body(ewe.Empty)

    _ -> next()
  }
}

fn add_html_extensions(
  request: Request,
  next: fn(Request) -> Response,
) -> Response {
  case filepath.extension(request.path) {
    Ok(_) -> next(request)
    Error(_) if request.path == "/" ->
      next(Request(..request, path: "/index.html"))
    Error(_) -> next(Request(..request, path: request.path <> ".html"))
  }
}

fn serve_static_assets(request: Request, next: fn() -> Response) -> Response {
  use <- serve_dev_assets(request)
  use <- serve_assets(request)

  next()
}

fn serve_assets(request: Request, next: fn() -> Response) -> Response {
  let path = filepath.join("assets", request.path)

  case serve_asset(path) {
    Ok(response) -> response
    Error(_) -> next()
  }
}

fn serve_dev_assets(request: Request, next: fn() -> Response) -> Response {
  let path = filepath.join("priv", request.path)

  case serve_asset(path) {
    Ok(response) -> response
    Error(_) -> next()
  }
}

fn serve_asset(path: String) -> Result(Response, Nil) {
  let mime = case filepath.extension(path) {
    Ok("css") -> "text/css"
    Ok("js") -> "application/javascript"
    Ok("html") -> "text/html"
    Ok("png") -> "image/png"
    Ok("jpg") -> "image/jpeg"
    Ok("jpeg") -> "image/jpeg"
    Ok("gif") -> "image/gif"
    Ok("svg") -> "image/svg+xml"
    _ -> "application/octet-stream"
  }

  case ewe.file(path, offset: None, limit: None) {
    Ok(file) ->
      response.new(200)
      |> response.set_header("content-type", mime)
      |> response.set_body(file)
      |> Ok

    Error(_) -> Error(Nil)
  }
}

// FILE WATCHER ----------------------------------------------------------------

type Change {
  NoteChanged
  CssChanged
}

fn watcher(
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
      polly.Created(path: "notes" <> slug)
      | polly.Changed(path: "notes" <> slug) -> {
        let slug = filepath.strip_extension(slug)
        let _ =
          booklet.update(vault, fn(vault) {
            case note.read(slug) {
              Ok(note) -> vault.insert(vault, note)
              Error(_) -> vault
            }
          })

        Nil
      }

      polly.Changed(path: "src/app.css") -> {
        tailwind.run("src/app.css")
        |> booklet.set(css, _)

        list.each(group_registry.members(channel, "*"), {
          process.send(_, CssChanged)
        })
      }

      polly.Deleted(path: "notes" <> slug) -> {
        let slug = filepath.strip_extension(slug)
        let _ = booklet.update(vault, vault.delete(_, slug))

        Nil
      }

      _ -> Nil
    }
  })
  |> polly.supervised
}
