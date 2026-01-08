// IMPORTS ---------------------------------------------------------------------

import app/data/date
import app/data/djot
import app/data/unicode
import app/error.{type Error}
import app/view/document
import filepath
import frontmatter
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
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

pub type Note {
  Note(
    slug: String,
    title: String,
    summary: Option(String),
    tags: List(String),
    created: Date,
    updated: Option(Date),
    references: Set(String),
    content: Document,
  )
}

// CONSTANTS -------------------------------------------------------------------

const empty = "---
created = {now}
---

# {title}

This is a summary for the note. It appears in its own section before the main
note content, but only if it's a single paragraph.
"

// CONSTRUCTORS ----------------------------------------------------------------

/// Generate a new note and write it to disk. This will prefill the created date
/// as the current date and set the title to whatever is provided.
///
pub fn new(slug: String, title: String) -> Result(Note, Error) {
  let path = filepath.join("notes", slug <> ".md")
  let now = date.now()
  let source =
    empty
    |> string.replace("{now}", date.to_iso8601(now))
    |> string.replace("New note", title)

  use <- bool.guard(
    result.unwrap(simplifile.is_file(path), False),
    Error(error.NoteAlreadyExists(path)),
  )

  use _ <- result.try(
    simplifile.write(path, source)
    |> result.map_error(error.NoteCouldNotBeCreated(path, _)),
  )

  let note =
    Note(
      slug: case string.starts_with(slug, "/") {
        True -> slug
        False -> "/" <> slug
      },
      title:,
      summary: None,
      tags: [],
      created: now,
      updated: None,
      references: set.new(),
      content: jot.Document(
        content: [],
        references: dict.new(),
        reference_attributes: dict.new(),
        footnotes: dict.new(),
      ),
    )

  Ok(note)
}

/// Read a note from the vault given its slug.
///
pub fn read(slug: String) -> Result(Note, Error) {
  let path = filepath.join("notes", slug <> ".md")
  use source <- result.try(
    simplifile.read(path)
    |> result.map_error(error.NoteCouldNotBeRead(path, _)),
  )

  let frontmatter.Extracted(frontmatter, djot) = frontmatter.extract(source)
  let frontmatter =
    frontmatter
    |> option.unwrap("")
    |> tom.parse
    |> result.unwrap(dict.new())

  let document = jot.parse(djot)

  let tags = read_tags(slug, frontmatter)
  use created <- result.try(
    tom.get_date(frontmatter, ["created"])
    |> result.map_error(error.NoteMissingCreatedDate(slug, _)),
  )

  let updated =
    tom.get_date(frontmatter, ["updated"])
    |> option.from_result

  use #(title, summary, content) <- result.try(read_title_and_summary(
    slug,
    document,
  ))

  let references = read_references(content)

  let note =
    Note(
      slug:,
      title:,
      summary:,
      tags:,
      created:,
      updated:,
      references:,
      content:,
    )

  Ok(note)
}

fn read_tags(slug: String, frontmatter: Dict(String, Toml)) -> List(String) {
  let implicit =
    filepath.directory_name(slug)
    |> string.split("/")
    |> list.filter(fn(tag) { tag != "" })

  let explicit =
    tom.get_array(frontmatter, ["tags"])
    |> result.try(list.try_map(_, tom.as_string))
    |> result.unwrap([])

  list.unique(list.append(implicit, explicit))
}

fn read_title_and_summary(
  slug: String,
  document: Document,
) -> Result(#(String, Option(String), Document), Error) {
  case document.content {
    [jot.Heading(level: 1, ..) as h1, jot.Paragraph(..) as p, ..rest] -> {
      let title = djot.inline_text(h1.content)
      let summary = djot.inline_text(p.content) |> string.replace("\n", " ")

      Ok(#(title, Some(summary), Document(..document, content: rest)))
    }

    [jot.Heading(level: 1, ..) as h1, ..rest] -> {
      let title = djot.inline_text(h1.content)
      let summary = None

      Ok(#(title, summary, Document(..document, content: rest)))
    }

    _ -> Error(error.NoteMissingTitle(slug))
  }
}

fn read_references(document: Document) -> Set(String) {
  do_read_references(set.new(), document.content)
}

fn do_read_references(
  references: Set(String),
  content: List(jot.Container),
) -> Set(String) {
  case content {
    [] -> references

    [jot.Paragraph(content:, ..), ..rest] | [jot.Heading(content:, ..), ..rest] ->
      do_read_inline_references(references, content)
      |> do_read_references(rest)

    [jot.ThematicBreak, ..rest]
    | [jot.Codeblock(..), ..rest]
    | [jot.RawBlock(..), ..rest] -> do_read_references(references, rest)

    [jot.BulletList(items:, ..), ..rest] ->
      list.fold(items, references, do_read_references)
      |> do_read_references(rest)

    [jot.BlockQuote(items:, ..), ..rest] | [jot.Div(items:, ..), ..rest] ->
      do_read_references(references, items)
      |> do_read_references(rest)
  }
}

fn do_read_inline_references(
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
    | [jot.Text(..), ..rest] -> do_read_inline_references(references, rest)

    [jot.Link(content:, destination: jot.Reference("@" <> note), ..), ..rest] ->
      set.insert(references, "/" <> note)
      |> do_read_inline_references(content)
      |> do_read_inline_references(rest)

    [jot.Image(content:, ..), ..rest]
    | [jot.Span(content:, ..), ..rest]
    | [jot.Emphasis(content:), ..rest]
    | [jot.Strong(content:), ..rest]
    | [jot.Link(content:, ..), ..rest] ->
      do_read_inline_references(references, content)
      |> do_read_inline_references(rest)
  }
}

///
///
pub fn index(notes: List(Note)) -> Note {
  let notes =
    list.sort(notes, fn(a, b) {
      calendar.naive_date_compare(
        option.unwrap(b.updated, b.created),
        option.unwrap(a.updated, a.created),
      )
    })

  let slug = "/all"
  let title = "All notes"
  let summary = Some("All notes in the vault, sorted by most-recently updated.")
  let tags = []

  let assert Ok(oldest) = list.last(notes)
  let assert Ok(latest) = list.first(notes)

  let content =
    jot.parse({
      use list, note <- list.fold(notes, "")
      let item =
        "- [{title}]({slug})"
        |> string.replace("{title}", note.title)
        |> string.replace("{slug}", note.slug)

      let item = case note.summary {
        Some(summary) -> item <> " – " <> summary
        None -> item
      }

      list <> item <> "\n\n"
    })

  Note(
    slug:,
    title:,
    summary:,
    tags:,
    created: oldest.created,
    updated: Some(option.unwrap(latest.updated, latest.created)),
    // For index and tag notes, we consider the set of references to be empty as
    // the note content itself is a list of links to other notes.
    references: set.new(),
    content:,
  )
}

///
///
pub fn tag(name: String, notes: List(Note)) -> Note {
  let notes =
    list.sort(notes, fn(a, b) {
      calendar.naive_date_compare(
        option.unwrap(b.updated, b.created),
        option.unwrap(a.updated, a.created),
      )
    })

  let slug = "/tag/" <> name
  let title = "Notes tagged with " <> unicode.ldquote <> name <> unicode.rdquote
  let summary = None
  let tags = []

  let assert Ok(oldest) = list.last(notes)
  let assert Ok(latest) = list.first(notes)

  let content =
    jot.parse({
      use list, note <- list.fold(notes, "")
      let item =
        "- [{title}]({slug})"
        |> string.replace("{title}", note.title)
        |> string.replace("{slug}", note.slug)

      let item = case note.summary {
        Some(summary) -> item <> " – " <> summary
        None -> item
      }

      list <> item <> "\n"
    })

  Note(
    slug:,
    title:,
    summary:,
    tags:,
    created: oldest.created,
    updated: Some(option.unwrap(latest.updated, latest.created)),
    // For index and tag notes, we consider the set of references to be empty as
    // the note content itself is a list of links to other notes.
    references: set.new(),
    content:,
  )
}

// CONVERSIONS -----------------------------------------------------------------

pub fn to_document_meta(note: Note) -> document.Meta {
  document.Meta(
    title: note.title,
    description: note.summary |> option.unwrap(""),
    slug: note.slug,
    attributes: [],
  )
}

// VIEW ------------------------------------------------------------------------

pub fn view_header(note: Note) -> Element(_) {
  html.header([attribute.class("header")], [
    view_header_dates(note.created, note.updated),
    view_header_title(note.title),
    view_header_tags(note.tags),
  ])
}

fn view_header_dates(created: Date, updated: Option(Date)) -> Element(_) {
  html.div([attribute.class("dates")], [
    view_created_date(created),
    view_updated_date(updated),
  ])
}

fn view_created_date(date: Date) -> Element(_) {
  view_date(date, "🌱")
}

fn view_updated_date(date: Option(Date)) -> Element(_) {
  case date {
    None -> element.none()
    Some(date) -> view_date(date, "🪴")
  }
}

fn view_date(date: Date, emoji: String) -> Element(_) {
  html.p([], [
    html.span([attribute.aria_label("Created date"), attribute.class("emoji")], [
      html.text(emoji),
    ]),
    date.view([], date),
  ])
}

fn view_header_title(title: String) -> Element(_) {
  html.h1([attribute.class("mt-6 text-3xl text-orange-800")], [
    html.text(title),
  ])
}

fn view_header_tags(tags: List(String)) -> Element(_) {
  html.ul([attribute.class("flex flex-wrap gap-x-2 not-empty:mt-6")], {
    list.map(tags, fn(tag) {
      html.li([], [
        view_header_tag(tag),
      ])
    })
  })
}

fn view_header_tag(tag: String) -> Element(_) {
  let id =
    string.to_utf_codepoints(tag)
    |> list.map(string.utf_codepoint_to_int)
    |> int.sum

  let classes = case id % 8 {
    0 -> "tag bg-orange-50 text-black"
    1 -> "tag bg-orange-600 text-black"
    2 -> "tag bg-pink-50 text-black"
    3 -> "tag bg-pink-600 text-white"
    4 -> "tag bg-blue-600 text-white"
    5 -> "tag bg-blue-50 text-black"
    6 -> "tag bg-purple-50 text-black"
    _ -> "tag bg-purple-600 text-white"
  }

  html.a([attribute.href("/tag/" <> tag), attribute.class(classes)], [
    html.text(tag),
  ])
}

pub fn view_summary(note: Note) -> Element(_) {
  case note.summary {
    None -> element.none()
    Some(summary) ->
      html.div([attribute.class("summary")], [
        html.p([], [
          html.text(summary),
        ]),
      ])
  }
}

pub fn view_content(note: Note) -> Element(_) {
  html.div([attribute.class("content")], djot.view(note.content))
}
