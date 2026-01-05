// Set up WebSocket for live reloading
const ws = new WebSocket(
  `ws://${window.location.host}/.live${window.location.pathname}`,
);

ws.onmessage = function (event) {
  const data = JSON.parse(event.data);

  switch (data.type) {
    case "css":
      return replaceStyles(data.content);

    case "html":
      return replaceNote(data.content);
  }
};

ws.onopen = function () {
  console.log("Live reload WebSocket connected");
};

ws.onclose = function () {
  console.log("Live reload WebSocket disconnected");
};

ws.onerror = function (error) {
  console.error("WebSocket error:", error);
};

function replaceStyles(css) {
  const target = document.querySelector(
    'link[href="/app.css"], style[data-css-reload]',
  );
  const style = document.createElement("style");

  style.setAttribute("data-css-reload", "true");
  style.textContent = css;

  target.parentNode.replaceChild(style, target);
}

function replaceNote(html) {
  const target = document.querySelector(".note");
  const template = document.createElement("template");

  template.innerHTML = html;
  const note = template.content;

  target.parentNode.replaceChild(note, target);
}
