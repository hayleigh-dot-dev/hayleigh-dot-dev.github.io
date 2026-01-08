// IMPORTS ---------------------------------------------------------------------

import clique

import clique/bounds.{type Bounds}
import clique/edge
import clique/handle.{type Handle, Handle}
import clique/node
import clique/transform.{type Transform, FitOptions}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/float
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html

// MAIN ------------------------------------------------------------------------

pub fn main() {
  use data <- promise.map(fetch_graph_data())

  let slug = read_note_slug()
  let app = lustre.application(init:, update:, view:)

  let assert Ok(_) = clique.register()
  let assert Ok(_) =
    lustre.start(app, "#graph", {
      StartArguments(slug:, graph: {
        case decode.run(data, graph_decoder()) {
          Ok(graph) -> graph
          Error(_) -> Graph(nodes: dict.new(), edges: [])
        }
      })
    })

  Nil
}

@external(javascript, "./graph.ffi.mjs", "readNoteSlug")
fn read_note_slug() -> String

@external(javascript, "./graph.ffi.mjs", "fetchGraphData")
fn fetch_graph_data() -> Promise(Dynamic)

fn graph_decoder() -> Decoder(Graph) {
  use nodes <- decode.field(
    "nodes",
    decode.dict(decode.string, {
      use slug <- decode.field("slug", decode.string)
      use size <- decode.field("size", decode.float)
      let force = #(0.0, 0.0)
      let mass = 5.0 +. size *. 2.0

      decode.success(Node(id: slug, x: 0.0, y: 0.0, force:, size:, mass:))
    }),
  )

  use edges <- decode.field(
    "edges",
    decode.list({
      use from <- decode.field("from", decode.string)
      use to <- decode.field("to", decode.string)
      let id = from <> "->" <> to
      let from = Handle(from, "handle")
      let to = Handle(to, "handle")

      decode.success(Edge(id:, source: from, target: to))
    }),
  )

  decode.success(Graph(nodes:, edges:))
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(focus: String, graph: Graph, viewport: Bounds, transform: Transform)
}

type Graph {
  Graph(nodes: Dict(String, Node), edges: List(Edge))
}

type Node {
  Node(
    id: String,
    x: Float,
    y: Float,
    force: #(Float, Float),
    size: Float,
    mass: Float,
  )
}

type Edge {
  Edge(id: String, source: Handle, target: Handle)
}

type StartArguments {
  StartArguments(slug: String, graph: Graph)
}

fn init(arguments: StartArguments) -> #(Model, Effect(Msg)) {
  let model =
    Model(
      focus: case dict.has_key(arguments.graph.nodes, arguments.slug) {
        True -> arguments.slug
        False -> "/index"
      },
      graph: arguments.graph,
      viewport: bounds.init(),
      transform: transform.init(),
    )
  let effect = measure_viewport()

  #(model, effect)
}

fn measure_viewport() -> Effect(Msg) {
  use dispatch, _ <- effect.before_paint()
  let bounds = do_measure_viewport()

  dispatch(ViewportChangedSize(viewport: bounds, initial: True))
}

@external(javascript, "./graph.ffi.mjs", "measureViewport")
fn do_measure_viewport() -> Bounds

// UPDATE ----------------------------------------------------------------------

type Msg {
  UserPannedViewport(transform: Transform)
  ViewportChangedSize(viewport: Bounds, initial: Bool)
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UserPannedViewport(transform:) -> {
      let model = Model(..model, transform:)
      let effect = effect.none()

      #(model, effect)
    }

    ViewportChangedSize(viewport:, initial: True) -> {
      let nodes =
        dict.map_values(model.graph.nodes, fn(id, node) {
          let #(x, y) = deterministic_position(id, viewport)

          Node(..node, x:, y:)
        })
      let graph = Graph(..model.graph, nodes:)
      let model = Model(..model, graph: layout(graph, 1000))

      case dict.get(model.graph.nodes, model.focus) {
        Error(_) -> #(model, effect.none())
        Ok(focus) -> {
          let transform = fit(viewport, focus)
          let model = Model(..model, viewport:, transform:)
          let effect = effect.none()

          #(model, effect)
        }
      }
    }

    ViewportChangedSize(viewport:, initial: False) ->
      case dict.get(model.graph.nodes, model.focus) {
        Error(_) -> #(model, effect.none())
        Ok(focus) -> {
          let transform = fit(viewport, focus)
          let model = Model(..model, viewport:, transform:)
          let effect = effect.none()

          #(model, effect)
        }
      }
  }
}

fn fit(viewport: Bounds, focus: Node) -> Transform {
  transform.fit_with(
    box: bounds.new(focus.x, focus.y, focus.size, focus.size),
    into: viewport,
    options: FitOptions(
      padding: #(200.0, 200.0),
      max_zoom: Some(1.5),
      min_zoom: Some(0.3),
    ),
  )
}

// LAYOUT HELPERS --------------------------------------------------------------

fn deterministic_position(id: String, viewport: Bounds) -> #(Float, Float) {
  let w = bounds.width(viewport)
  let h = bounds.height(viewport)

  let hash = hash_string(id)
  let x_hash = int.bitwise_and(hash, 0xFFFF)
  let y_hash = int.bitwise_and(int.bitwise_shift_right(hash, 16), 0xFFFF)

  let x = int.to_float(x_hash) /. 65_535.0 *. w -. { w /. 2.0 }
  let y = int.to_float(y_hash) /. 65_535.0 *. h -. { h /. 2.0 }

  #(x, y)
}

fn hash_string(s: String) -> Int {
  let bytes = string.to_utf_codepoints(s)
  use acc, codepoint <- list.fold(bytes, 0)
  let char_code = string.utf_codepoint_to_int(codepoint)
  int.bitwise_and(acc * 31 + char_code, 0x7FFFFFFF)
}

fn layout(graph: Graph, iterations: Int) -> Graph {
  use <- bool.guard(iterations <= 0, graph)
  let nodes = tick(graph.nodes, graph.edges, iterations)
  let graph = Graph(..graph, nodes:)

  layout(graph, iterations - 1)
}

const gravity_strength = 0.01

const repulsion_strength = 8000.0

const attraction_strength = 0.05

const damping = 0.1

const min_distance = 10.0

fn tick(
  nodes: Dict(String, Node),
  edges: List(Edge),
  iteration: Int,
) -> Dict(String, Node) {
  // Calculate cooling factor for simulated annealing
  let cooling = float.max(0.01, 1.0 -. int.to_float(iteration) /. 1000.0)

  // Reset forces
  let nodes = {
    use _, node <- dict.map_values(nodes)
    Node(..node, force: #(0.0, 0.0))
  }

  // Apply gravitational force towards center
  let nodes = {
    use _, node <- dict.map_values(nodes)
    let fx = float.negate(node.x) *. gravity_strength
    let fy = float.negate(node.y) *. gravity_strength

    Node(..node, force: #(node.force.0 +. fx, node.force.1 +. fy))
  }

  // Apply repulsive forces between all nodes
  let nodes = {
    use nodes, _, current <- dict.fold(nodes, nodes)
    use nodes, _, other <- dict.fold(nodes, nodes)
    use <- bool.guard(current.id == other.id, nodes)

    let dx = other.x -. current.x
    let dy = other.y -. current.y
    let distance_sq = dx *. dx +. dy *. dy
    let distance =
      float.max(
        min_distance,
        float.square_root(distance_sq) |> result.unwrap(min_distance),
      )

    // Repulsive force inversely proportional to distance squared
    let force_magnitude = repulsion_strength /. distance_sq
    let fx = { dx /. distance } *. force_magnitude
    let fy = { dy /. distance } *. force_magnitude

    let current = {
      let assert Ok(current) = dict.get(nodes, current.id)
      Node(..current, force: #(current.force.0 -. fx, current.force.1 -. fy))
    }

    let other = {
      let assert Ok(other) = dict.get(nodes, other.id)
      Node(..other, force: #(other.force.0 +. fx, other.force.1 +. fy))
    }

    nodes
    |> dict.insert(current.id, current)
    |> dict.insert(other.id, other)
  }

  // Apply attractive forces for connected nodes
  let nodes = {
    use nodes, edge <- list.fold(edges, nodes)
    let assert Ok(from) = dict.get(nodes, edge.source.node)
    let assert Ok(to) = dict.get(nodes, edge.target.node)

    let dx = to.x -. from.x
    let dy = to.y -. from.y
    let distance =
      float.max(
        min_distance,
        float.square_root(dx *. dx +. dy *. dy) |> result.unwrap(min_distance),
      )

    // Spring force proportional to distance
    let force_magnitude = attraction_strength *. distance
    let fx = { dx /. distance } *. force_magnitude
    let fy = { dy /. distance } *. force_magnitude

    let from = Node(..from, force: #(from.force.0 +. fx, from.force.1 +. fy))

    let to = Node(..to, force: #(to.force.0 -. fx, to.force.1 -. fy))

    nodes
    |> dict.insert(from.id, from)
    |> dict.insert(to.id, to)
  }

  // Update positions based on forces with damping and cooling
  let nodes = {
    use _, node <- dict.map_values(nodes)
    let vx = node.force.0 /. node.mass *. cooling *. damping
    let vy = node.force.1 /. node.mass *. cooling *. damping

    let x = node.x +. vx
    let y = node.y +. vy

    Node(..node, x:, y:, force: #(0.0, 0.0))
  }

  nodes
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  clique.root(
    [
      clique.initial_transform(model.transform),
      clique.on_resize(ViewportChangedSize(_, initial: False)),
      attribute.class("w-full h-full"),
      attribute.style("--clique-edge-colour", "var(--color-blue-200)"),
    ],
    [
      clique.nodes({
        use nodes, key, data <- dict.fold(model.graph.nodes, [])
        let html = view_node(data, model.focus)

        [#(key, html), ..nodes]
      }),

      clique.edges({
        use Edge(id:, ..) as data <- list.map(model.graph.edges)
        let key = id
        let html = view_edge(data)

        #(key, html)
      }),
    ],
  )
}

fn view_node(data: Node, focus: String) -> Element(msg) {
  let size = [
    #("width", float.to_string(data.size) <> "px"),
    #("height", float.to_string(data.size) <> "px"),
  ]

  clique.node(data.id, [node.initial_position(data.x, data.y)], [
    html.div(
      [
        attribute.class("flex relative justify-center items-center"),
        attribute.class("rounded-full transition-opacity bg-blue"),
        attribute.class("hover:text-black/100"),
        attribute.class(case data.id == focus {
          True -> "text-black/100"
          False -> "text-black/20"
        }),
        attribute.styles(size),
      ],
      [
        clique.handle("handle", [
          attribute.class("pointer-events-none size-[1px] -z-10"),
        ]),
        html.a(
          [
            node.nodrag(),
            attribute.class("inline-block absolute w-max text-xs"),
            attribute.style("bottom", float.to_string(data.size) <> "px"),
            attribute.href(data.id),
          ],
          [
            html.text(data.id),
          ],
        ),
      ],
    ),
  ])
}

fn view_edge(data: Edge) -> Element(msg) {
  clique.edge(data.source, data.target, [edge.linear()], [])
}
