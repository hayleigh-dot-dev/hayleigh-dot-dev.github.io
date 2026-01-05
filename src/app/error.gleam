// IMPORTS ---------------------------------------------------------------------

import gleam/string
import simplifile
import tom

// TYPES -----------------------------------------------------------------------

pub type Error {
  GraphCouldNotReadNotes(reason: simplifile.FileError)
  NoteCouldNotBeRead(path: String, reason: simplifile.FileError)
  NoteInvalidFrontmatter(slug: String, reason: tom.ParseError, source: String)
  NoteMissingSummary(slug: String)
  NoteMissingTitle(slug: String)
  NoteUnknownReference(note: String, reference: String)
}

// CONVERSIONS -----------------------------------------------------------------

pub fn to_string(error: Error) -> String {
  case error {
    _ -> string.inspect(error)
  }
}
