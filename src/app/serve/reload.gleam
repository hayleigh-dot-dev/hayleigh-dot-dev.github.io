// IMPORTS ---------------------------------------------------------------------

import app/data/vault.{type Vault}
import app/serve/watcher.{type Change}
import booklet.{type Booklet}
import ewe.{type Request}
import filepath
import gleam/erlang/process.{type Name}
import gleam/json
import group_registry.{type Message}
import lustre/element

//

pub fn start(
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

    ewe.User(watcher.Note) -> {
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

    ewe.User(watcher.Styles) -> {
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
