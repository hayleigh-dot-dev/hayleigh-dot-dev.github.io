// IMPORTS ---------------------------------------------------------------------

import app/data/note.{type Note}
import app/data/vault.{type Vault}
import app/view/date
import gleam/bool
import gleam/dict
import gleam/string
import lustre/attribute.{attribute}
import lustre/element.{type Element, element}

// CONSTANTS -------------------------------------------------------------------

const xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"

const root = "https://hayleigh.dev"

// CONSTRUCTORS ----------------------------------------------------------------

pub fn from_vault(vault: Vault) -> String {
  let rss =
    rss(
      "Hayleigh's blog",
      "Hi stranger, I'm Hayleigh. Here is where I share my thoughts, collect
      some notes, and try to carve out a little slice of the internet that feels like
      home.",
      dict.fold(vault.notes, [], fn(items, _, note) {
        use <- bool.guard(note.slug == "/404", items)
        use <- bool.guard(note.slug == "/all", items)
        use <- bool.guard(string.starts_with(note.slug, "/tag/"), items)

        [item(note), ..items]
      }),
    )

  xml <> element.to_readable_string(rss)
}

// ELEMENTS --------------------------------------------------------------------

fn rss(
  title: String,
  description: String,
  children: List(Element(_)),
) -> Element(_) {
  element("rss", [attribute("version", "2.0")], [
    element("channel", [], [
      element("title", [], [element.text(title)]),
      element.advanced("", "link", [], [element.text(root)], False, False),
      element.namespaced(
        "http://www.w3.org/2005/Atom",
        "link",
        [attribute.rel("self"), attribute.href(root <> "/rss.xml")],
        [],
      ),
      element("description", [], [element.text(description)]),
      element.fragment(children),
    ]),
  ])
}

fn item(note: Note) -> Element(_) {
  element("item", [], [
    element("guid", [], [element.text(root <> note.slug)]),
    element("title", [], [element.text(note.title)]),
    element.advanced(
      "",
      "link",
      [],
      [element.text(root <> note.slug)],
      False,
      False,
    ),
    element("pubDate", [], [element.text(date.to_rfc822(note.created))]),
  ])
}
