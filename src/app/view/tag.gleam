// IMPORTS ---------------------------------------------------------------------

import gleam/int
import gleam/list
import gleam/string
import lustre/attribute.{type Attribute}
import lustre/element.{type Element}
import lustre/element/html

// VIEW ------------------------------------------------------------------------

pub fn view(attributes: List(Attribute(_)), tag: String) -> Element(_) {
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

  html.a(
    [attribute.href("/tag/" <> tag), attribute.class(classes), ..attributes],
    [html.text(tag)],
  )
}
