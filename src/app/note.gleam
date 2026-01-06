// IMPORTS ---------------------------------------------------------------------

import app/error.{type Error}
import app/view/box
import app/view/date
import app/view/djot
import app/view/document
import app/view/tag
import filepath
import frontmatter.{Extracted}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/pair
import gleam/result
import gleam/set.{type Set}
import gleam/string
import gleam/time/calendar.{type Date}
import jot.{type Document, Document}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import simplifile
import tom.{type Toml}

// TYPES -----------------------------------------------------------------------

pub type NoteMetadata {
  NoteMetadata(
    slug: String,
    title: String,
    summary: String,
    tags: List(String),
    created: Date,
    updated: Option(Date),
  )
}

pub type Note {
  Note(meta: NoteMetadata, document: Document)
}

// CONSTRUCTORS ----------------------------------------------------------------

///
///
pub fn read(path: String, vault: String) -> Result(Note, Error) {
  use text <- result.try(
    simplifile.read(path)
    |> result.map_error(error.NoteCouldNotBeRead(path, _)),
  )

  let slug =
    path
    |> string.replace(vault, "")
    |> string.replace(".md", "")

  use #(frontmatter, document) <- result.try(case frontmatter.extract(text) {
    Extracted(frontmatter:, content: text) -> {
      let djot = jot.parse(text)

      case frontmatter {
        Some(toml) ->
          tom.parse(toml)
          |> result.map_error(error.NoteInvalidFrontmatter(slug, _, toml))
          |> result.map(pair.new(_, djot))
        None -> Ok(#(dict.new(), djot))
      }
    }
  })

  use #(title, document) <- result.try(read_title(slug, frontmatter, document))

  use summary <- result.try(case tom.get_string(frontmatter, ["summary"]) {
    Ok("") | Error(_) -> Error(error.NoteMissingSummary(slug))
    Ok(summary) -> Ok(summary)
  })

  let path_tags =
    filepath.directory_name(slug)
    |> string.split("/")
    |> list.filter(fn(tag) { tag != "" })

  let tags =
    tom.get_array(frontmatter, ["tags"])
    |> result.try(list.try_map(_, tom.as_string))
    |> result.unwrap([])
    |> list.append(path_tags)
    |> list.unique

  use created <- result.try(
    tom.get_date(frontmatter, ["created"])
    |> result.map_error(error.NoteMissingCreatedDate(slug, _)),
  )

  let updated = case tom.get_date(frontmatter, ["updated"]) {
    Ok(date) -> Some(date)
    Error(_) -> None
  }

  let meta = NoteMetadata(slug:, title:, summary:, tags:, created:, updated:)
  let note = Note(meta:, document:)

  Ok(note)
}

fn read_title(
  slug: String,
  frontmatter: Dict(String, Toml),
  document: Document,
) -> Result(#(String, Document), Error) {
  let frontmatter_title = tom.get_string(frontmatter, ["title"])
  let #(document_title, document) = case document.content {
    [jot.Heading(level: 1, content: inline, ..), ..content] -> #(
      djot.inline_text(inline),
      Document(..document, content:),
    )

    _ -> #("", document)
  }

  case frontmatter_title, document_title {
    Ok(""), "" | Error(_), "" -> Error(error.NoteMissingTitle(slug))
    Ok(title), _ -> Ok(#(title, document))
    Error(_), title -> Ok(#(title, document))
  }
}

///
///
pub fn tag(name: String, notes: List(NoteMetadata)) -> Note {
  let slug = "/tags/" <> name
  let title = "Posts tagged with “" <> name <> "”"
  let summary = ""
  let tags = []

  let assert Ok(created) =
    notes
    |> list.sort(fn(a, b) { calendar.naive_date_compare(a.created, b.created) })
    |> list.first
    |> result.map(fn(first) { first.created })

  let updated =
    notes
    |> list.sort(fn(a, b) {
      calendar.naive_date_compare(
        b.updated |> option.unwrap(b.created),
        a.updated |> option.unwrap(a.created),
      )
    })
    |> list.first
    |> result.map(fn(last) { last.updated })
    |> result.unwrap(None)

  let meta = NoteMetadata(slug:, title:, summary:, tags:, created:, updated:)
  let document =
    list.map(notes, fn(note) {
      "- [" <> note.title <> "](" <> note.slug <> ") – " <> note.summary
    })
    |> string.join("\n\n")
    |> jot.parse

  Note(meta:, document:)
}

///
///
pub fn all(notes: List(NoteMetadata)) -> Note {
  let slug = "/all"
  let title = "All my notes"
  let summary =
    "A complete list of all my notes, sorted by most-recently updated."

  let tags = ["meta"]
  let notes =
    notes
    |> list.sort(fn(a, b) {
      calendar.naive_date_compare(
        b.updated |> option.unwrap(b.created),
        a.updated |> option.unwrap(a.created),
      )
    })

  let assert Ok(created) =
    notes
    |> list.last
    |> result.map(fn(last) { last.created })

  let assert Ok(updated) =
    notes
    |> list.first
    |> result.map(fn(first) { first.updated |> option.unwrap(first.created) })

  let meta =
    NoteMetadata(
      slug:,
      title:,
      summary:,
      tags:,
      created:,
      updated: Some(updated),
    )

  let document =
    list.map(notes, fn(note) {
      "- [" <> note.title <> "](" <> note.slug <> ") – " <> note.summary
    })
    |> string.join("\n\n")
    |> jot.parse

  Note(meta:, document:)
}

// QUERIES ---------------------------------------------------------------------

///
///
pub fn references(note: Note) -> List(String) {
  set.new()
  |> do_references(note.document.content)
  |> set.to_list
}

fn do_references(
  references: Set(String),
  content: List(jot.Container),
) -> Set(String) {
  case content {
    [] -> references

    [jot.Paragraph(content:, ..), ..rest] | [jot.Heading(content:, ..), ..rest] ->
      do_inline_references(references, content)
      |> do_references(rest)

    [jot.ThematicBreak, ..rest]
    | [jot.Codeblock(..), ..rest]
    | [jot.RawBlock(..), ..rest] -> do_references(references, rest)

    [jot.BulletList(items:, ..), ..rest] ->
      list.fold(items, references, do_references)
      |> do_references(rest)

    [jot.BlockQuote(items:, ..), ..rest] | [jot.Div(items:, ..), ..rest] ->
      do_references(references, items)
      |> do_references(rest)
  }
}

fn do_inline_references(
  references: Set(String),
  content: List(jot.Inline),
) -> Set(String) {
  case content {
    [] -> references

    [jot.Linebreak, ..rest]
    | [jot.NonBreakingSpace, ..rest]
    | [jot.Code(..), ..rest]
    | [jot.Footnote(..), ..rest]
    | [jot.MathInline(..), ..rest]
    | [jot.MathDisplay(..), ..rest]
    | [jot.Text(..), ..rest] -> do_inline_references(references, rest)

    [jot.Link(content:, destination: jot.Reference("@" <> note), ..), ..rest] ->
      set.insert(references, "/" <> note)
      |> do_inline_references(content)
      |> do_inline_references(rest)

    [jot.Image(content:, ..), ..rest]
    | [jot.Span(content:, ..), ..rest]
    | [jot.Emphasis(content:), ..rest]
    | [jot.Strong(content:), ..rest]
    | [jot.Link(content:, ..), ..rest] ->
      do_inline_references(references, content)
      |> do_inline_references(rest)
  }
}

// VIEW ------------------------------------------------------------------------

pub fn document_meta(note: Note) -> document.Meta {
  document.Meta(
    title: note.meta.title,
    description: note.meta.summary,
    slug: note.meta.slug,
    attributes: [],
  )
}

pub fn view(note: Note, referenced_in: List(NoteMetadata)) -> Element(_) {
  box.view([attribute.class("note border-orange")], {
    html.main([], [
      view_header(note.meta),
      view_summary(note.meta),
      view_content(note.document),
      view_footer(referenced_in),
    ])
  })
}

// VIEW HEADER -----------------------------------------------------------------

fn view_header(meta: NoteMetadata) -> Element(_) {
  html.header([attribute.class("px-4 pt-8 mx-auto max-w-xl header")], [
    html.div([attribute.class("flex justify-between items-baseline text-xs")], [
      view_created_date(meta.created),
      view_updated_date(meta.updated),
    ]),

    html.h1([attribute.class("mt-6 text-3xl text-orange-800")], [
      html.text(meta.title),
    ]),

    html.ul([attribute.class("flex flex-wrap gap-x-2 not-empty:mt-6")], {
      list.map(meta.tags, fn(tag) {
        html.li([], [
          tag.view([], tag),
        ])
      })
    }),
  ])
}

fn view_created_date(date: Date) -> Element(_) {
  html.p([], [
    html.span(
      [
        attribute.aria_label("Created date"),
        attribute.class(
          "inline-flex justify-center items-center mr-2 bg-orange-50 rounded-full size-6",
        ),
      ],
      [
        html.text("🌱"),
      ],
    ),
    date.view([], date),
  ])
}

fn view_updated_date(date: Option(Date)) -> Element(_) {
  case date {
    None -> element.none()
    Some(date) ->
      html.p([], [
        date.view([attribute.class("italic")], date),
        html.span(
          [
            attribute.aria_label("Updated date"),
            attribute.class(
              "inline-flex justify-center items-center ml-2 bg-orange-50 rounded-full size-6",
            ),
          ],
          [
            html.text("🪴"),
          ],
        ),
      ])
  }
}

// VIEW SUMMARY ----------------------------------------------------------------

fn view_summary(meta: NoteMetadata) -> Element(_) {
  use <- bool.guard(meta.summary == "", element.none())

  html.div([attribute.class("py-4 bg-orange-50 summary")], [
    html.p([attribute.class("px-4 mx-auto max-w-xl text-xl italic")], [
      html.text(meta.summary),
    ]),
  ])
}

// VIEW CONTENT ----------------------------------------------------------------

fn view_content(document: Document) -> Element(_) {
  html.div([attribute.class("content")], djot.view(document))
}

// VIEW FOOTER -----------------------------------------------------------------

fn view_footer(references: List(NoteMetadata)) -> Element(_) {
  use <- bool.guard(references == [], element.none())

  element.fragment([
    html.hr([attribute.class("border-orange")]),
    html.footer([attribute.class("footer")], [
      html.h2([attribute.class("mb-4 text-lg")], [
        html.text("Referenced in"),
      ]),
      html.ul([], {
        list.map(references, fn(reference) {
          html.li([], [
            html.a([attribute.href(reference.slug)], [
              html.text(reference.title),
            ]),
            html.text(" – " <> reference.summary),
          ])
        })
      }),
    ]),
  ])
}
