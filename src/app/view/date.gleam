// IMPORTS ---------------------------------------------------------------------

import gleam/int
import gleam/string
import gleam/time/calendar.{type Date}
import lustre/attribute.{type Attribute, attribute}
import lustre/element.{type Element}
import lustre/element/html

// CONVERSIONS -----------------------------------------------------------------

pub fn to_iso8601(date: Date) -> String {
  "year-month-day"
  |> string.replace("year", int.to_string(date.year))
  |> string.replace("month", pad(calendar.month_to_int(date.month)))
  |> string.replace("day", pad(date.day))
}

pub fn to_rfc822(date: Date) -> String {
  let month = case date.month {
    calendar.January -> "Jan"
    calendar.February -> "Feb"
    calendar.March -> "Mar"
    calendar.April -> "Apr"
    calendar.May -> "May"
    calendar.June -> "Jun"
    calendar.July -> "Jul"
    calendar.August -> "Aug"
    calendar.September -> "Sep"
    calendar.October -> "Oct"
    calendar.November -> "Nov"
    calendar.December -> "Dec"
  }

  "day month year 00:00:00 GMT"
  |> string.replace("day", int.to_string(date.day))
  |> string.replace("month", month)
  |> string.replace("year", int.to_string(date.year))
}

pub fn to_human_readable(date: Date) -> String {
  "day month, year"
  |> string.replace("day", int.to_string(date.day))
  |> string.replace("month", calendar.month_to_string(date.month))
  |> string.replace("year", int.to_string(date.year))
}

// VIEW ------------------------------------------------------------------------

pub fn view(attributes: List(Attribute(_)), date: Date) -> Element(_) {
  let datetime = to_iso8601(date)
  let text = to_human_readable(date)

  html.time([attribute("datetime", datetime), ..attributes], [html.text(text)])
}

fn pad(int: Int) -> String {
  string.pad_start(int.to_string(int), 2, "0")
}
