import ewe.{type Request, type Response}
import filepath
import gleam/erlang/application
import gleam/http/request.{Request}
import gleam/http/response
import gleam/option.{None}

pub fn redirect_root(request: Request, next: fn() -> Response) -> Response {
  case request.path {
    "/" ->
      response.new(302)
      |> response.set_header("location", "/index.html")
      |> response.set_body(ewe.Empty)

    _ -> next()
  }
}

pub fn add_html_extensions(
  request: Request,
  next: fn(Request) -> Response,
) -> Response {
  case filepath.extension(request.path) {
    Ok(_) -> next(request)
    Error(_) if request.path == "/" ->
      next(Request(..request, path: "/index.html"))
    Error(_) -> next(Request(..request, path: request.path <> ".html"))
  }
}

pub fn serve_static_assets(request: Request, next: fn() -> Response) -> Response {
  let assert Ok(priv) = application.priv_directory("app")
  let path = filepath.join(priv, request.path)

  let mime = case filepath.extension(path) {
    Ok("css") -> "text/css"
    Ok("js") -> "application/javascript"
    Ok("html") -> "text/html"
    Ok("png") -> "image/png"
    Ok("jpg") -> "image/jpeg"
    Ok("jpeg") -> "image/jpeg"
    Ok("gif") -> "image/gif"
    Ok("svg") -> "image/svg+xml"
    _ -> "application/octet-stream"
  }

  case ewe.file(path, offset: None, limit: None) {
    Ok(file) ->
      response.new(200)
      |> response.set_header("content-type", mime)
      |> response.set_body(file)

    Error(_) -> next()
  }
}
