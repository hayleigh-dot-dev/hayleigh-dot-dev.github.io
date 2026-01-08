//
export function readNoteSlug() {
  return window.location.pathname.replace(".html", "");
}

//
export function fetchGraphData() {
  const cached = window.sessionStorage.getItem("graph-data");

  if (cached) {
    return Promise.resolve(readLocalGraphData(cached));
  } else {
    return fetchRemoteGraphData();
  }
}

function readLocalGraphData(cached) {
  try {
    return JSON.parse(cached);
  } catch {
    return {};
  }
}

async function fetchRemoteGraphData() {
  try {
    const response = await fetch("/graph-data.json");
    const json = await response.json();

    window.sessionStorage.setItem("graph-data", JSON.stringify(json));

    return json;
  } catch {
    return {};
  }
}

//
export function measureViewport() {
  const viewport = document.querySelector("clique-viewport");

  if (!viewport) return [0, 0, 0, 0];

  const bounds = viewport.getBoundingClientRect();

  return [bounds.x, bounds.y, bounds.width, bounds.height];
}
