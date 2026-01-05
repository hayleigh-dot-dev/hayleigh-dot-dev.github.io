import lustre/attribute.{type Attribute}
import lustre/element.{type Element}
import lustre/element/html

pub fn view(attributes: List(Attribute(_)), content: Element(_)) -> Element(_) {
  html.div([attribute.class("box"), ..attributes], [
    html.div([], []),
    html.div([], []),
    content,
    html.div([], []),
    html.div([], []),
  ])
}
