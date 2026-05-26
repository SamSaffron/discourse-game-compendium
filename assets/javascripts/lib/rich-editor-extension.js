const TERMS = {
  sharp: {
    name: "Sharp",
    slug: "sharp",
    kind: "enchantment",
    description: "Increases damage on this card by X.",
  },
};

function slugify(name) {
  return name
    .toLowerCase()
    .replace(/[’']/g, "")
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function titleize(slug) {
  return slug
    .split("_")
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function normalizeCardName(name) {
  const upgraded = /\+$/.test(name.trim());
  const baseName = name.trim().replace(/\++$/, "");
  return { baseName, upgraded };
}

function imageForSlug(slug) {
  return `/game-compendium/assets/${slug}/image.png`;
}

function cardAttrsForName(name) {
  const { baseName, upgraded } = normalizeCardName(name);
  const slug = slugify(baseName);
  return { slug, name: baseName || titleize(slug), image: imageForSlug(slug, upgraded), upgraded };
}

function termAttrsForName(name) {
  const slug = slugify(name);
  const term = TERMS[slug];
  return term ? { slug, name: term.name, kind: term.kind, description: term.description } : null;
}

function decodeHtmlText(text) {
  const textarea = document.createElement("textarea");
  textarea.innerHTML = text || "";
  return textarea.value;
}

function textFromRenderedToken(token) {
  const content = token.content || "";
  const nameMatch = content.match(/class="game-compendium-ref-name">([^<]+)</);
  if (nameMatch) {
    return decodeHtmlText(nameMatch[1]);
  }
  const altMatch = content.match(/\balt="([^"]+)"/);
  if (altMatch) {
    return decodeHtmlText(altMatch[1]);
  }
}

function cardDOM(attrs) {
  return [
    "span",
    {
      class: "game-compendium-ref game-compendium-card-ref game-compendium-rich-card-ref",
      "data-game-compendium-slug": attrs.slug,
      "data-game-compendium-upgraded": attrs.upgraded ? "true" : undefined,
      tabindex: "0",
      contenteditable: "false",
    },
    ["span", { class: "game-compendium-ref-name" }, attrs.name + (attrs.upgraded ? "+" : "")],
    [
      "span",
      { class: "game-compendium-preview", role: "tooltip" },
      [
        "img",
        {
          src: attrs.image,
          alt: attrs.name + (attrs.upgraded ? "+" : ""),
          loading: "lazy",
        },
      ],
    ],
  ];
}

function termDOM(attrs) {
  return [
    "span",
    {
      class: `game-compendium-ref game-compendium-term-ref game-compendium-term-${attrs.kind || "term"} game-compendium-rich-term-ref`,
      "data-game-compendium-slug": attrs.slug,
      tabindex: "0",
      contenteditable: "false",
    },
    ["span", { class: "game-compendium-ref-name" }, attrs.name],
    [
      "span",
      { class: "game-compendium-term-tooltip", role: "tooltip" },
      ["strong", attrs.name],
      ["span", attrs.description || ""],
    ],
  ];
}

function blockDOM(attrs) {
  return [
    "div",
    {
      class: "game-compendium-card-block game-compendium-rich-card-block",
      "data-game-compendium-slug": attrs.slug,
      "data-game-compendium-upgraded": attrs.upgraded ? "true" : undefined,
      contenteditable: "false",
    },
    [
      "img",
      {
        src: attrs.image,
        alt: attrs.name + (attrs.upgraded ? "+" : ""),
        loading: "lazy",
      },
    ],
  ];
}

function attrsFromCardDom(dom) {
  const slug = dom.getAttribute("data-game-compendium-slug") || slugify(dom.textContent || "");
  const upgraded =
    dom.getAttribute("data-game-compendium-upgraded") === "true" || /\+$/.test(dom.textContent || "");
  const name = (dom.textContent || titleize(slug)).trim().replace(/\++$/, "");
  return { slug, name, image: imageForSlug(slug, upgraded), upgraded };
}

function isOnlyTextOnLine(state, start, end) {
  const $start = state.doc.resolve(start);
  const $end = state.doc.resolve(end);
  return (
    $start.sameParent($end) &&
    $start.parent.isTextblock &&
    $start.parentOffset === 0 &&
    $end.parentOffset === $end.parent.content.size
  );
}

function replaceLineWithBlock(state, start, end, node) {
  const $start = state.doc.resolve(start);
  return state.tr.replaceWith($start.before(), $start.after(), node);
}

const extension = {
  nodeSpec: {
    game_compendium_card_ref: {
      inline: true,
      group: "inline",
      atom: true,
      selectable: true,
      attrs: {
        slug: { default: "" },
        name: { default: "" },
        image: { default: "" },
        upgraded: { default: false },
      },
      parseDOM: [{ tag: "span.game-compendium-card-ref", getAttrs: attrsFromCardDom }],
      toDOM: (node) => cardDOM(node.attrs),
    },
    game_compendium_term_ref: {
      inline: true,
      group: "inline",
      atom: true,
      selectable: true,
      attrs: {
        slug: { default: "" },
        name: { default: "" },
        kind: { default: "term" },
        description: { default: "" },
      },
      parseDOM: [
        {
          tag: "span.game-compendium-term-ref",
          getAttrs(dom) {
            const slug = dom.getAttribute("data-game-compendium-slug") || slugify(dom.textContent || "");
            const term = TERMS[slug];
            return term ? { slug, name: term.name, kind: term.kind, description: term.description } : false;
          },
        },
      ],
      toDOM: (node) => termDOM(node.attrs),
    },
    game_compendium_card_block: {
      group: "block",
      atom: true,
      selectable: true,
      defining: true,
      attrs: {
        slug: { default: "" },
        name: { default: "" },
        image: { default: "" },
        upgraded: { default: false },
      },
      parseDOM: [{ tag: "div.game-compendium-card-block", getAttrs: attrsFromCardDom }],
      toDOM: (node) => blockDOM(node.attrs),
    },
  },
  parse: {
    game_compendium_card_inline: {
      node: "game_compendium_card_ref",
      getAttrs: (token) => cardAttrsForName(textFromRenderedToken(token) || ""),
    },
    game_compendium_term_inline: {
      node: "game_compendium_term_ref",
      getAttrs: (token) => termAttrsForName(textFromRenderedToken(token) || "") || false,
    },
    game_compendium_card_block: {
      node: "game_compendium_card_block",
      getAttrs: (token) => cardAttrsForName(textFromRenderedToken(token) || ""),
    },
  },
  inputRules: [
    {
      match: /\[\[([^\]]+)\]\]$/,
      handler: (state, match, start, end) => {
        const termAttrs = termAttrsForName(match[1]);
        const attrs = termAttrs ? null : cardAttrsForName(match[1]);
        const type = termAttrs ? state.schema.nodes.game_compendium_term_ref : state.schema.nodes.game_compendium_card_ref;

        if (!termAttrs && isOnlyTextOnLine(state, start, end)) {
          return replaceLineWithBlock(
            state,
            start,
            end,
            state.schema.nodes.game_compendium_card_block.create(attrs)
          );
        }

        return state.tr.replaceWith(start, end, type.create(termAttrs || attrs));
      },
    },
  ],
  serializeNode: {
    game_compendium_card_ref(state, node) {
      state.write(`[[${node.attrs.name}${node.attrs.upgraded ? "+" : ""}]]`);
    },
    game_compendium_term_ref(state, node) {
      state.write(`[[${node.attrs.name}]]`);
    },
    game_compendium_card_block(state, node) {
      state.ensureNewLine();
      state.write(`[[${node.attrs.name}${node.attrs.upgraded ? "+" : ""}]]\n\n`);
    },
  },
};

export default extension;
