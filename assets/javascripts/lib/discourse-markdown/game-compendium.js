// Game compendium asset/term markdown-it plugin for Discourse.

const TERMS = {
  sharp: {
    id: "SHARP",
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

function cardImagePath(slug) {
  return `/game-compendium/assets/${slug}/image.png`;
}

function buildCardRefHtml(name, slug, escapeHtml, upgraded = false) {
  const displayName = (name || titleize(slug)) + (upgraded ? "+" : "");
  const eName = escapeHtml(displayName);
  const eSlug = escapeHtml(slug);
  const eSrc = escapeHtml(cardImagePath(slug, upgraded));
  const upgradedAttr = upgraded ? ' data-game-compendium-upgraded="true"' : "";

  return (
    '<span class="game-compendium-ref game-compendium-card-ref" data-game-compendium-slug="' +
    eSlug +
    '"' +
    upgradedAttr +
    ' tabindex="0">' +
    '<span class="game-compendium-ref-name">' +
    eName +
    "</span>" +
    '<span class="game-compendium-preview" role="tooltip">' +
    '<img src="' +
    eSrc +
    '" alt="' +
    eName +
    '" loading="lazy">' +
    "</span></span>"
  );
}

function buildTermRefHtml(name, slug, term, escapeHtml) {
  const eName = escapeHtml(term.name || name);
  const eSlug = escapeHtml(slug);
  const eDesc = escapeHtml(term.description || "");
  const kindClass = "game-compendium-term-" + escapeHtml(term.kind || "term");

  return (
    '<span class="game-compendium-ref game-compendium-term-ref ' +
    kindClass +
    '" data-game-compendium-slug="' +
    eSlug +
    '" tabindex="0">' +
    '<span class="game-compendium-ref-name">' +
    eName +
    "</span>" +
    '<span class="game-compendium-term-tooltip" role="tooltip">' +
    "<strong>" +
    eName +
    "</strong><span>" +
    eDesc +
    "</span>" +
    "</span></span>"
  );
}

function expandInlineRefs(content, escapeHtml) {
  const re = /\[\[([^\]]+)\]\]/g;
  let result = null;
  let match;
  let pos = 0;

  while ((match = re.exec(content)) !== null) {
    const name = match[1];
    const upgraded = /\+$/.test(name.trim());
    const baseName = name.trim().replace(/\++$/, "");
    const slug = slugify(baseName);
    const term = TERMS[slug];

    result = result || [];
    if (match.index > pos) {
      result.push({ type: "text", content: content.slice(pos, match.index) });
    }

    if (term) {
      result.push({
        type: "game_compendium_term_inline",
        content: buildTermRefHtml(name, slug, term, escapeHtml),
        meta: { slug },
      });
    } else {
      result.push({
        type: "game_compendium_card_inline",
        content: buildCardRefHtml(baseName, slug, escapeHtml, upgraded),
        meta: { slug, name: baseName, upgraded },
      });
    }

    pos = match.index + match[0].length;
  }

  if (result && pos < content.length) {
    result.push({ type: "text", content: content.slice(pos) });
  }

  return result;
}

function processGameCompendiumInline(state) {
  const escapeHtml = state.md.utils.escapeHtml;

  for (let i = 0; i < state.tokens.length; i++) {
    const blockToken = state.tokens[i];
    if (blockToken.type !== "inline") {
      continue;
    }

    const children = blockToken.children;
    if (!children) {
      continue;
    }

    for (let j = children.length - 1; j >= 0; j--) {
      const child = children[j];
      if (child.type !== "text") {
        continue;
      }

      const fragments = expandInlineRefs(child.content, escapeHtml);
      if (!fragments) {
        continue;
      }

      const newTokens = fragments.map(({ type, content, meta }) => {
        const tok = new state.Token(type, "", 0);
        tok.content = content;
        tok.meta = meta;
        return tok;
      });
      children.splice(j, 1, ...newTokens);
    }
  }
}

function buildCardBlockHtml(slug, name, escapeHtml, upgraded = false) {
  const displayName = (name || titleize(slug)) + (upgraded ? "+" : "");
  const eName = escapeHtml(displayName);
  const eSlug = escapeHtml(slug);
  const eSrc = escapeHtml(cardImagePath(slug, upgraded));
  const upgradedAttr = upgraded ? ' data-game-compendium-upgraded="true"' : "";

  return (
    '<div class="game-compendium-card-block" data-game-compendium-slug="' +
    eSlug +
    '"' +
    upgradedAttr +
    ">\n" +
    '<img src="' +
    eSrc +
    '" alt="' +
    eName +
    '" loading="lazy">\n' +
    "</div>\n"
  );
}

function convertParagraphCardRefsToBlocks(state) {
  for (let i = 0; i < state.tokens.length - 2; i++) {
    const open = state.tokens[i];
    const inline = state.tokens[i + 1];
    const close = state.tokens[i + 2];
    if (
      open.type !== "paragraph_open" ||
      inline.type !== "inline" ||
      close.type !== "paragraph_close"
    ) {
      continue;
    }

    const rawChildren = inline.children || [];
    const firstContentIndex = rawChildren.findIndex(
      (child) => child.type !== "text" || child.content.trim().length > 0
    );
    if (
      firstContentIndex === -1 ||
      rawChildren[firstContentIndex].type !== "game_compendium_card_inline"
    ) {
      continue;
    }

    const { slug, name, upgraded } = rawChildren[firstContentIndex].meta || {};
    if (!slug) {
      continue;
    }

    const token = new state.Token("game_compendium_card_block", "", 0);
    token.content = buildCardBlockHtml(slug, name, state.md.utils.escapeHtml, upgraded);
    token.map = open.map;

    const remainingChildren = rawChildren.slice(firstContentIndex + 1);
    if (remainingChildren[0]?.type === "text") {
      remainingChildren[0].content = remainingChildren[0].content.replace(/^\s+/, "");
    }
    const hasRemainingContent = remainingChildren.some(
      (child) => child.type !== "text" || child.content.trim().length > 0
    );

    if (!hasRemainingContent) {
      state.tokens.splice(i, 3, token);
    } else {
      inline.children = remainingChildren;
      inline.content = remainingChildren.map((child) => child.content || "").join("");
      state.tokens.splice(i, 0, token);
      i++;
    }
  }
}

export function setup(helper) {
  if (!helper.markdownIt) {
    return;
  }

  helper.registerOptions((opts, siteSettings) => {
    opts.features["game-compendium-assets"] = !!siteSettings.game_compendium_enabled;
  });

  helper.allowList({
    custom(tag, name, value) {
      if (name !== "class") {
        return false;
      }

      const allowedClasses = new Set([
        "game-compendium-ref",
        "game-compendium-card-ref",
        "game-compendium-term-ref",
        "game-compendium-term-enchantment",
        "game-compendium-ref-name",
        "game-compendium-preview",
        "game-compendium-term-tooltip",
        "game-compendium-card-block",
      ]);
      const classes = value.split(/\s+/).filter(Boolean);
      return (
        (tag === "span" || tag === "div") &&
        classes.length > 0 &&
        classes.every((klass) => allowedClasses.has(klass))
      );
    },
  });

  helper.allowList([
    "span[data-game-compendium-slug]",
    "span[data-game-compendium-upgraded]",
    "span[tabindex]",
    "span[role]",
    "div[data-game-compendium-slug]",
    "div[data-game-compendium-upgraded]",
    "img[loading]",
  ]);

  helper.registerPlugin((md) => {
    if (!md.options.discourse.features["game-compendium-assets"]) {
      return;
    }

    md.renderer.rules.game_compendium_card_inline = (tokens, idx) => tokens[idx].content;
    md.renderer.rules.game_compendium_term_inline = (tokens, idx) => tokens[idx].content;
    md.renderer.rules.game_compendium_card_block = (tokens, idx) => tokens[idx].content;
    md.core.ruler.push("game-compendium-inline", processGameCompendiumInline);
    md.core.ruler.after("game-compendium-inline", "game-compendium-card-blocks", convertParagraphCardRefsToBlocks);
  });
}
