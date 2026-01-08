// IMPORTS ---------------------------------------------------------------------

import app/data/note.{type Note}
import app/error
import app/view/box
import app/view/document
import filepath
import gleam/bool
import gleam/dict.{type Dict}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/set.{type Set}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import simplifile

// TYPES -----------------------------------------------------------------------

pub type Vault {
  Vault(
    notes: Dict(String, Note),
    links: Set(#(String, String)),
    tags: Dict(String, List(String)),
  )
}

// CONSTRUCTORS ----------------------------------------------------------------

pub fn load() -> Result(Vault, error.Error) {
  use files <- result.try(
    simplifile.get_files("notes")
    |> result.map_error(error.GraphCouldNotReadNotes),
  )

  let init = #(dict.new(), dict.new())
  use #(notes, tags) <- result.try({
    use #(notes, tags), file <- list.try_fold(files, init)
    let assert "notes" <> slug = filepath.strip_extension(file)
    use note <- result.try(note.read(slug))
    let notes = dict.insert(notes, note.slug, note)
    let tags =
      list.fold(note.tags, tags, fn(tags, tag) {
        dict.upsert(tags, tag, fn(notes) {
          case notes {
            None -> [note.slug]
            Some(existing) -> [note.slug, ..existing]
          }
        })
      })

    Ok(#(notes, tags))
  })

  let links =
    dict.fold(notes, set.new(), fn(links, _, note) {
      note.references
      |> set.map(fn(reference) { #(note.slug, reference) })
      |> set.union(links)
    })

  Ok(Vault(notes:, links:, tags:))
}

pub fn index(vault: Vault) -> Note {
  note.index(dict.delete(vault.notes, "/404") |> dict.values)
}

// MANIPULATIONS ---------------------------------------------------------------

pub fn insert(vault: Vault, note: Note) -> Vault {
  let vault = delete(vault, note.slug)
  let notes = dict.insert(vault.notes, note.slug, note)
  let tags =
    list.fold(note.tags, vault.tags, fn(tags, tag) {
      dict.upsert(tags, tag, fn(notes) {
        case notes {
          None -> [note.slug]
          Some(existing) -> [note.slug, ..existing]
        }
      })
    })

  let links =
    note.references
    |> set.map(fn(reference) { #(note.slug, reference) })
    |> set.union(vault.links)

  Vault(notes:, links:, tags:)
}

pub fn delete(vault: Vault, slug: String) -> Vault {
  use <- bool.guard(!dict.has_key(vault.notes, slug), vault)
  let notes = dict.delete(vault.notes, slug)
  let tags =
    dict.fold(vault.tags, dict.new(), fn(tags, tag, notes) {
      case list.filter(notes, fn(note_slug) { note_slug != slug }) {
        [] -> tags
        [note] if note == slug -> tags
        notes -> dict.insert(tags, tag, notes)
      }
    })

  let links =
    set.filter(vault.links, fn(link) { link.0 != slug && link.1 != slug })

  Vault(notes:, links:, tags:)
}

// CONVERSIONS -----------------------------------------------------------------

pub fn to_graph_json(vault: Vault) -> Json {
  json.object([
    #("nodes", to_nodes_json(vault.notes, vault.tags, set.to_list(vault.links))),
    #("edges", to_edges_json(vault.notes, vault.tags, set.to_list(vault.links))),
  ])
}

fn to_nodes_json(
  notes: Dict(String, Note),
  tags: Dict(String, List(String)),
  links: List(#(String, String)),
) -> Json {
  let entries = [
    #("/all", {
      json.object([
        #("slug", json.string("/all")),
        #("size", json.int(dict.size(notes) + dict.size(tags))),
      ])
    }),
  ]

  let entries =
    dict.fold(notes, entries, fn(entries, slug, _) {
      use <- bool.guard(slug == "/404", entries)
      let size =
        10 + list.count(links, fn(link) { link.0 == slug || link.1 == slug })

      let json =
        json.object([
          #("slug", json.string(slug)),
          #("size", json.int(size)),
        ])

      [#(slug, json), ..entries]
    })

  let entries =
    dict.fold(tags, entries, fn(entries, tag, references) {
      let slug = "/tag/" <> tag
      let size =
        10
        + list.length(references)
        + list.count(links, fn(link) { link.1 == slug })

      let json =
        json.object([
          #("slug", json.string(slug)),
          #("size", json.int(size)),
        ])

      [#(slug, json), ..entries]
    })

  json.object(entries)
}

fn to_edges_json(
  notes: Dict(String, Note),
  tags: Dict(String, List(String)),
  links: List(#(String, String)),
) -> Json {
  let edges =
    list.filter_map(links, fn(link) {
      use <- bool.guard(link.0 == "/404" || link.1 == "/404", Error(Nil))

      let from = link.0
      let to = link.1

      Ok(
        json.object([
          #("from", json.string(from)),
          #("to", json.string(to)),
        ]),
      )
    })

  let edges =
    dict.fold(tags, edges, fn(edges, tag, references) {
      let to = "/tag/" <> tag
      let edges =
        list.append(edges, {
          list.map(references, fn(from) {
            json.object([
              #("from", json.string(from)),
              #("to", json.string(to)),
            ])
          })
        })

      [
        json.object([
          #("from", json.string("/all")),
          #("to", json.string(to)),
        ]),
        ..edges
      ]
    })

  let edges =
    dict.fold(notes, edges, fn(edges, slug, _) {
      use <- bool.guard(slug == "/404", edges)

      [
        json.object([
          #("from", json.string("/all")),
          #("to", json.string(slug)),
        ]),
        ..edges
      ]
    })

  json.preprocessed_array(edges)
}

// VIEW ------------------------------------------------------------------------

pub fn view(vault: Vault, slug: String) -> #(document.Meta, Element(_)) {
  let #(meta, body) = case slug {
    "/all" -> view_all(vault)
    "/tag/" <> tag -> view_tag(vault, tag)
    "/404" -> view_not_found(vault)

    slug ->
      dict.get(vault.notes, slug)
      |> result.map(view_note(vault, _))
      |> result.lazy_unwrap(fn() { view_not_found(vault) })
  }

  #(meta, {
    html.main([attribute.class("p-4 mx-auto max-w-3xl")], [
      box.view([attribute.class("note border-orange")], body),
    ])
  })
}

fn view_all(vault: Vault) -> #(document.Meta, Element(_)) {
  let notes = dict.values(vault.notes)
  use <- bool.lazy_guard(notes == [], fn() { view_not_found(vault) })
  let note = index(vault)

  view_note(vault, note)
}

fn view_tag(vault: Vault, tag: String) -> #(document.Meta, Element(_)) {
  let notes =
    dict.get(vault.tags, tag)
    |> result.unwrap([])
    |> list.filter_map(dict.get(vault.notes, _))

  use <- bool.lazy_guard(notes == [], fn() { view_not_found(vault) })
  let note = note.tag(tag, notes)

  view_note(vault, note)
}

fn view_not_found(vault: Vault) -> #(document.Meta, Element(_)) {
  let assert Ok(not_found) = dict.get(vault.notes, "/404")

  view_note(vault, not_found)
}

fn view_note(vault: Vault, note: Note) -> #(document.Meta, Element(_)) {
  let meta = note.to_document_meta(note)
  let body =
    html.div([], [
      note.view_header(note),
      note.view_summary(note),
      note.view_content(note),
      html.hr([attribute.class("ml-[-1lh] w-[calc(100%+2lh)] border-orange")]),
      html.div([attribute.id("graph")], []),
      view_note_references(vault, note),
    ])

  #(meta, body)
}

fn view_note_references(vault: Vault, note: Note) -> Element(_) {
  let references =
    set.fold(vault.links, [], fn(references, link) {
      case dict.get(vault.notes, link.0) {
        Ok(referent) if link.1 == note.slug -> [referent, ..references]
        Ok(_) | Error(_) -> references
      }
    })

  use <- bool.guard(references == [], element.none())
  let references = list.map(references, view_note_reference)

  element.fragment([
    html.hr([attribute.class("ml-[-1lh] w-[calc(100%+2lh)] border-orange")]),
    html.div([attribute.class("references")], [
      html.h2([attribute.class("mb-4 text-lg")], [
        html.text("Referenced in"),
      ]),
      html.ul([], references),
    ]),
  ])
}

fn view_note_reference(note: Note) -> Element(_) {
  html.li([], [
    html.a([attribute.href(note.slug)], [
      html.text(note.title),
    ]),
    case note.summary {
      None -> element.none()
      Some(summary) -> html.text(" – " <> summary)
    },
  ])
}
