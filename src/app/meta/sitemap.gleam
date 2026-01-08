// IMPORTS ---------------------------------------------------------------------

import app/data/vault.{type Vault}
import app/view/date
import gleam/bool
import gleam/dict
import gleam/option.{type Option, None, Some}
import gleam/time/calendar.{type Date}
import lustre/element.{type Element, element}

// CONSTANTS -------------------------------------------------------------------

const xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"

const root = "https://hayleigh.dev"

// CONSTRUCTORS ----------------------------------------------------------------

pub fn from_vault(vault: Vault) -> String {
  let sitemap =
    urlset(
      dict.fold(vault.notes, [], fn(urls, slug, note) {
        use <- bool.guard(note.slug == "/404", urls)

        [url(root <> slug, note.updated), ..urls]
      }),
    )

  xml <> element.to_readable_string(sitemap)
}

// ELEMENTS --------------------------------------------------------------------

fn urlset(children: List(Element(_))) -> Element(_) {
  element.namespaced(
    "http://www.sitemaps.org/schemas/sitemap/0.9",
    "urlset",
    [],
    children,
  )
}

fn url(loc: String, lastmod: Option(Date)) -> Element(_) {
  element("url", [], [
    element("loc", [], [element.text(loc)]),
    case lastmod {
      None -> element.none()
      Some(date) ->
        element("lastmod", [], [
          element.text(date.to_iso8601(date)),
        ])
    },
  ])
}
