import contour
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{Some}
import jot.{type Document}
import just
import lustre/attribute.{type Attribute, attribute}
import lustre/element.{type Element}
import lustre/element/html

// QUERIES ---------------------------------------------------------------------

///
///
pub fn inline_text(content: List(jot.Inline)) -> String {
  do_inline_text(content, "")
}

fn do_inline_text(content: List(jot.Inline), title: String) -> String {
  case content {
    [] -> title

    [jot.Linebreak, ..rest] | [jot.NonBreakingSpace, ..rest] ->
      do_inline_text(rest, title <> " ")

    [jot.Text(content), ..rest] | [jot.Code(content:), ..rest] ->
      do_inline_text(rest, title <> content)

    [jot.Link(content:, ..), ..rest]
    | [jot.Span(content:, ..), ..rest]
    | [jot.Emphasis(content:), ..rest]
    | [jot.Strong(content:), ..rest] ->
      do_inline_text(rest, do_inline_text(content, title))

    [jot.Footnote(..), ..rest]
    | [jot.Image(..), ..rest]
    | [jot.MathInline(..), ..rest]
    | [jot.MathDisplay(..), ..rest] -> do_inline_text(rest, title)
  }
}

// VIEW ------------------------------------------------------------------------

pub fn view(document: Document) -> List(Element(_)) {
  view_block_content(document.content)
}

fn view_block_content(content: List(jot.Container)) -> List(Element(_)) {
  use block <- list.map(content)

  case block {
    jot.ThematicBreak -> element.none()

    jot.Paragraph(attributes:, content:) ->
      html.p(view_attributes(attributes), view_inline_content(content))

    jot.Heading(attributes:, level: 1, content:) ->
      html.h1(view_attributes(attributes), view_inline_content(content))

    jot.Heading(attributes:, level: 2, content:) ->
      html.h2(view_attributes(attributes), view_inline_content(content))

    jot.Heading(attributes:, level: 3, content:) ->
      html.h3(view_attributes(attributes), view_inline_content(content))

    jot.Heading(attributes:, level: 4, content:) ->
      html.h4(view_attributes(attributes), view_inline_content(content))

    jot.Heading(attributes:, level: 5, content:) ->
      html.h5(view_attributes(attributes), view_inline_content(content))

    jot.Heading(attributes:, level: _, content:) ->
      html.h6(view_attributes(attributes), view_inline_content(content))

    jot.Codeblock(attributes:, language: Some("gleam"), content:) ->
      html.pre(view_attributes(attributes), [
        element.unsafe_raw_html("", "code", [], contour.to_html(content)),
      ])

    jot.Codeblock(attributes:, language: Some("js"), content:) ->
      html.pre(view_attributes(attributes), [
        element.unsafe_raw_html("", "code", [], just.highlight_html(content)),
      ])

    jot.Codeblock(attributes:, language: _, content:) -> {
      echo block
      html.pre(view_attributes(attributes), [
        html.code([], [html.text(content)]),
      ])
    }

    jot.RawBlock(content:) -> element.unsafe_raw_html("", "div", [], content)

    jot.BulletList(items:, ..) -> {
      html.ul([], {
        list.map(items, fn(block) { html.li([], view_block_content(block)) })
      })
    }

    jot.BlockQuote(attributes:, items:) ->
      html.blockquote(view_attributes(attributes), view_block_content(items))

    jot.Div(attributes:, items:) ->
      html.div(view_attributes(attributes), view_block_content(items))
  }
}

fn view_attributes(attributes: Dict(String, String)) -> List(Attribute(_)) {
  dict.fold(attributes, [], fn(attributes, name, value) {
    [attribute(name, value), ..attributes]
  })
}

fn view_inline_content(content: List(jot.Inline)) -> List(Element(_)) {
  use inline <- list.map(content)

  case inline {
    jot.Linebreak -> html.br([])

    jot.NonBreakingSpace -> html.text("&nbsp;")

    jot.Text(content) -> html.text(content)

    jot.Link(attributes:, content:, destination: jot.Url("")) ->
      html.span(view_attributes(attributes), view_inline_content(content))

    jot.Link(attributes:, content:, destination:) -> {
      let href = case destination {
        jot.Reference("@" <> note) -> attribute.href("/" <> note <> ".html")
        jot.Reference(_) -> panic
        jot.Url(url) -> attribute.href(url)
      }

      html.a(
        [href, ..view_attributes(attributes)],
        view_inline_content(content),
      )
    }

    jot.Image(attributes:, content:, destination:) ->
      case destination {
        jot.Reference(_) -> panic
        jot.Url(url) ->
          html.img([
            attribute.src(url),
            attribute.alt(inline_text(content)),
            ..view_attributes(attributes)
          ])
      }

    jot.Span(attributes:, content:) ->
      html.span(view_attributes(attributes), view_inline_content(content))

    jot.Emphasis(content:) -> html.em([], view_inline_content(content))

    jot.Strong(content:) -> html.strong([], view_inline_content(content))

    jot.Footnote(..) -> panic

    jot.Code(content:) -> html.code([], [html.text(content)])

    jot.MathInline(..) -> panic

    jot.MathDisplay(..) -> panic
  }
}
