import { readFileSync } from "fs";

import { defineConfig } from "astro/config";
import mdx from "@astrojs/mdx";
import react from "@astrojs/react";
import tailwind from "@astrojs/tailwind";

const gleamGrammar = readFileSync("./assets/gleam.tmLanguage.json", "utf8");

// https://astro.build/config
export default defineConfig({
  integrations: [react(), tailwind(), mdx()],
  markdown: {
    shikiConfig: {
      theme: "vitesse-dark",
      langs: [{ id: "gleam", scopeName: "source.gleam", grammar: JSON.parse(gleamGrammar) }],
    },
  },
});
