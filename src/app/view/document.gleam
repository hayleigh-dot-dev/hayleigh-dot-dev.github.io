import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

// TYPES -----------------------------------------------------------------------

pub type Meta {
  Meta(
    title: String,
    description: String,
    slug: String,
    attributes: List(#(String, String)),
  )
}

// VIEW ------------------------------------------------------------------------

pub fn view(
  meta: Meta,
  head: List(Element(_)),
  body: List(Element(_)),
) -> Element(_) {
  html.html([attribute.lang("en")], [
    html.head([], [
      html.title([], meta.title),

      html.meta([attribute.charset("UTF-8")]),
      html.meta([
        attribute.name("viewport"),
        attribute.content("width=device-width, initial-scale=1"),
      ]),
      html.meta([
        attribute.name("description"),
        attribute.content(meta.description),
      ]),

      element.fragment(
        list.map(meta.attributes, fn(attribute) {
          html.meta([
            attribute.name(attribute.0),
            attribute.content(attribute.1),
          ])
        }),
      ),

      // OPEN GRAPH TAGS -------------------------------------------------------
      html.meta([attribute.name("og:title"), attribute.content(meta.title)]),
      html.meta([
        attribute.name("og:description"),
        attribute.content(meta.description),
      ]),
      html.meta([
        attribute.name("og:url"),
        attribute.content("https://hayleigh.dev/" <> meta.slug),
      ]),
      html.meta([attribute.name("og:type"), attribute.content("article")]),

      // FAVICON ---------------------------------------------------------------
      html.link([
        attribute.rel("icon"),
        attribute.href(
          "data:image/svg+xml,<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><text y=\".9em\" font-size=\"90\">🪴</text></svg>",
        ),
      ]),

      // FONTS & STYLES --------------------------------------------------------
      html.link([
        attribute.rel("preconnect"),
        attribute.href("https://fonts.googleapis.com"),
      ]),

      html.link([
        attribute.rel("preconnect"),
        attribute.href("https://fonts.gstatic.com"),
        attribute.crossorigin(""),
      ]),

      html.link([
        attribute.rel("stylesheet"),
        attribute.href(
          "https://fonts.googleapis.com/css2?family=Space+Mono:ital,wght@0,400;0,700;1,400;1,700&family=Young+Serif&display=swap",
        ),
      ]),

      html.link([
        attribute.rel("stylesheet"),
        attribute.href("/app.css"),
      ]),

      element.fragment(head),
    ]),

    html.body([], [
      element.fragment(body),
      html.footer([attribute.class("bg-stone-900")], [
        html.div([attribute.class("max-w-[1700px]")], []),
      ]),
    ]),
  ])
}
