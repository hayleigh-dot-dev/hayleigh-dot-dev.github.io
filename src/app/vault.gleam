// IMPORTS ---------------------------------------------------------------------

import app/error.{type Error}
import app/note.{type Note, type NoteMetadata}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/set.{type Set}
import gleam/string
import simplifile

// TYPES -----------------------------------------------------------------------

pub type Vault {
  Vault(
    source: String,
    notes: Dict(String, Note),
    links: Set(Link),
    tags: Set(String),
  )
}

pub type Link {
  Link(from: String, to: String)
}

// CONSTRUCTORS ----------------------------------------------------------------

pub fn new(source: String) -> Result(Vault, Error) {
  use notes <- result.try(
    simplifile.get_files(source)
    |> result.map_error(error.GraphCouldNotReadNotes),
  )

  use #(notes, tags) <- result.try({
    use #(notes, tags), path <- list.try_fold(notes, #(dict.new(), dict.new()))
    use note <- result.try(note.read(path, source))
    let notes = dict.insert(notes, note.meta.slug, note)
    let tags = {
      use tags, key <- list.fold(note.meta.tags, tags)
      use tag <- dict.upsert(tags, key)

      case tag {
        Some(notes) -> [note.meta, ..notes]
        None -> [note.meta]
      }
    }

    Ok(#(notes, tags))
  })

  let init =
    Vault(
      source:,
      notes:,
      links: set.new(),
      tags: set.from_list(dict.keys(tags)),
    )

  let vault =
    dict.fold(tags, init, fn(vault, tag, references) {
      let note = note.tag(tag, references)
      let notes = dict.insert(vault.notes, note.meta.slug, note)
      let links =
        list.fold(references, vault.links, fn(links, reference) {
          set.insert(links, Link(note.meta.slug, reference.slug))
        })

      Vault(..vault, notes:, links:)
    })

  use vault <- result.try(
    dict.fold(notes, Ok(vault), fn(graph, _, note) {
      use vault <- result.try(graph)
      let references = note.references(note)

      use links <- result.try({
        use links, reference <- list.try_fold(references, vault.links)
        case dict.has_key(vault.notes, reference) {
          True -> Ok(set.insert(links, Link(note.meta.slug, reference)))
          False -> Error(error.NoteUnknownReference(note.meta.slug, reference))
        }
      })

      Ok(Vault(..vault, links:))
    }),
  )

  Ok(vault)
}

// QUERIES ---------------------------------------------------------------------

pub fn references(vault: Vault, to note: String) -> List(NoteMetadata) {
  use notes, Link(from:, to:) <- set.fold(vault.links, [])
  use <- bool.guard(to != note, notes)
  use <- bool.guard(from == "/all" || from == "/404", notes)
  use <- bool.guard(string.starts_with(from, "/tags/"), notes)

  case dict.get(vault.notes, from) {
    Ok(reference) -> [reference.meta, ..notes]
    Error(_) -> notes
  }
}

// MANIPULATIONS ---------------------------------------------------------------

pub fn add(vault: Vault, note: Note) -> Result(Vault, Error) {
  let notes = dict.insert(vault.notes, note.meta.slug, note)
  let references = note.references(note)
  use links <- result.try({
    use links, reference <- list.try_fold(references, vault.links)
    case dict.has_key(vault.notes, reference) {
      True -> Ok(set.insert(links, Link(note.meta.slug, reference)))
      False -> Error(error.NoteUnknownReference(note.meta.slug, reference))
    }
  })

  Ok(Vault(..vault, notes:, links:))
}

pub fn load(vault: Vault, path: String) -> Result(Vault, Error) {
  use note <- result.try(note.read(path, vault.source))
  use vault <- result.try(add(vault, note))

  Ok(vault)
}

pub fn remove(vault: Vault, slug: String) -> Vault {
  let notes = dict.delete(vault.notes, slug)
  let links =
    set.filter(vault.links, fn(link) { link.from != slug && link.to != slug })

  let tags_to_remove =
    set.filter(vault.tags, fn(tag) {
      case dict.get(vault.notes, tag) {
        Error(_) -> False
        Ok(index) ->
          case note.references(index) {
            [reference] if reference == slug -> True
            _ -> False
          }
      }
    })

  let notes = set.fold(tags_to_remove, notes, dict.delete)
  let tags = set.difference(vault.tags, tags_to_remove)

  Vault(..vault, notes:, links:, tags:)
}
