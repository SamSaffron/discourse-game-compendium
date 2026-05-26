import { loadCards, slugify } from "./cards";

let tooltip;
let activeAnchor;
let hideTimer;
let listenersInstalled = false;

function ensureTooltip() {
  if (tooltip) {
    return tooltip;
  }

  tooltip = document.createElement("div");
  tooltip.className = "game-compendium-hover-portal";
  tooltip.setAttribute("role", "tooltip");
  tooltip.hidden = true;
  document.body.appendChild(tooltip);

  return tooltip;
}

function clearHideTimer() {
  if (hideTimer) {
    clearTimeout(hideTimer);
    hideTimer = null;
  }
}

function hideTooltip() {
  clearHideTimer();
  activeAnchor = null;

  if (tooltip) {
    tooltip.hidden = true;
    tooltip.replaceChildren();
  }
}

function scheduleHide() {
  clearHideTimer();
  hideTimer = setTimeout(hideTooltip, 80);
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function positionTooltip(anchor) {
  if (!tooltip || tooltip.hidden || !anchor) {
    return;
  }

  const rect = anchor.getBoundingClientRect();
  const tipRect = tooltip.getBoundingClientRect();
  const gap = 10;
  const margin = 8;
  let left = rect.left + rect.width / 2 - tipRect.width / 2;
  left = clamp(left, margin, window.innerWidth - tipRect.width - margin);

  const preferBelow = tooltip.classList.contains(
    "game-compendium-hover-portal--below",
  );
  let top = preferBelow ? rect.bottom + gap : rect.top - tipRect.height - gap;

  if (preferBelow && top + tipRect.height > window.innerHeight - margin) {
    top = rect.top - tipRect.height - gap;
  } else if (!preferBelow && top < margin) {
    top = rect.bottom + gap;
  }

  top = clamp(top, margin, window.innerHeight - tipRect.height - margin);
  tooltip.style.left = `${Math.round(left)}px`;
  tooltip.style.top = `${Math.round(top)}px`;
}

function cardDescriptionFrom(anchor) {
  const value = anchor.dataset.gameCompendiumDescription || "";
  return value.trim();
}

function cardImageFrom(anchor) {
  const description = cardDescriptionFrom(anchor);
  const inlineImg = anchor.querySelector(".game-compendium-preview img");

  if (inlineImg) {
    return {
      src: inlineImg.currentSrc || inlineImg.src,
      alt: inlineImg.alt || anchor.textContent.trim(),
      description,
    };
  }

  if (
    anchor.matches(
      ".game-compendium-pm-card-ref, .game-compendium-pm-block-ref",
    )
  ) {
    const text = anchor.textContent.trim();
    const m = text.match(/^\[\[([^\]]+)\]\]$/);

    if (m) {
      const name = m[1].trim();
      const slug = slugify(name.replace(/\++$/, ""));

      return {
        src: `/game-compendium/assets/${slug}/image.png`,
        alt: name,
        description,
      };
    }
  }

  return null;
}

function resetTooltipClasses(...classesToAdd) {
  const tip = ensureTooltip();
  tip.classList.remove(
    "game-compendium-hover-portal--below",
    "game-compendium-hover-portal--card",
    "game-compendium-hover-portal--term",
  );
  tip.classList.add(...classesToAdd);
  tip.replaceChildren();

  return tip;
}

function showCardTooltip(anchor) {
  const imgData = cardImageFrom(anchor);

  if (!imgData?.src) {
    return;
  }

  clearHideTimer();
  activeAnchor = anchor;

  const tip = resetTooltipClasses("game-compendium-hover-portal--card");
  const img = document.createElement("img");
  img.src = imgData.src;
  img.alt = imgData.alt;
  img.loading = "eager";
  img.decoding = "async";
  tip.appendChild(img);

  if (imgData.description) {
    const description = document.createElement("div");
    description.className = "game-compendium-hover-portal__card-description";
    description.textContent = imgData.description;
    tip.appendChild(description);
  }

  tip.hidden = false;
  requestAnimationFrame(() => positionTooltip(anchor));

  if (!img.complete) {
    img.addEventListener("load", () => positionTooltip(anchor), { once: true });
  }
}

function showCardDescriptionTooltip(anchor) {
  const description = cardDescriptionFrom(anchor);

  if (!description) {
    return;
  }

  clearHideTimer();
  activeAnchor = anchor;

  const tip = resetTooltipClasses("game-compendium-hover-portal--below");
  const descriptionEl = document.createElement("div");
  descriptionEl.className = "game-compendium-hover-portal__card-description";
  descriptionEl.textContent = description;
  tip.appendChild(descriptionEl);
  tip.hidden = false;
  requestAnimationFrame(() => positionTooltip(anchor));
}

function showTermTooltip(anchor) {
  const source = anchor.querySelector(".game-compendium-term-tooltip");

  if (!source) {
    return;
  }

  clearHideTimer();
  activeAnchor = anchor;

  const tip = resetTooltipClasses("game-compendium-hover-portal--term");
  tip.replaceChildren(source.cloneNode(true));
  tip.hidden = false;
  requestAnimationFrame(() => positionTooltip(anchor));
}

function anchorForEventTarget(target) {
  if (!(target instanceof Element)) {
    return null;
  }

  return target.closest(
    ".game-compendium-card-ref, .game-compendium-card-block, .game-compendium-term-ref, .game-compendium-pm-card-ref, .game-compendium-pm-block-ref",
  );
}

function showFor(anchor) {
  if (!anchor) {
    return;
  }

  if (anchor.matches(".game-compendium-card-block")) {
    showCardDescriptionTooltip(anchor);
  } else if (
    anchor.matches(
      ".game-compendium-card-ref, .game-compendium-pm-card-ref, .game-compendium-pm-block-ref",
    )
  ) {
    showCardTooltip(anchor);
  } else if (anchor.matches(".game-compendium-term-ref")) {
    showTermTooltip(anchor);
  }
}

async function enrichCompendiumDescriptions(elem) {
  const refs = [
    ...elem.querySelectorAll(
      ".game-compendium-card-ref, .game-compendium-card-block",
    ),
  ];

  if (!refs.length) {
    return;
  }

  const cards = await loadCards();
  const cardsBySlug = new Map(cards.map((card) => [card.slug, card]));

  refs.forEach((ref) => {
    const slug = ref.dataset.gameCompendiumSlug;
    const card = cardsBySlug.get(slug);
    const description = card?.description?.trim();

    if (!description) {
      return;
    }

    ref.dataset.gameCompendiumDescription = description;
  });
}

export function decorateCompendium(elem) {
  elem
    .querySelectorAll(".game-compendium-ref, .game-compendium-card-block")
    .forEach((ref) =>
      ref.setAttribute("data-game-compendium-tooltip-ready", "true"),
    );

  enrichCompendiumDescriptions(elem);
}

export function installGlobalTooltipListeners() {
  if (listenersInstalled) {
    return;
  }

  listenersInstalled = true;

  document.addEventListener("mouseover", (event) => {
    const anchor = anchorForEventTarget(event.target);

    if (!anchor || anchor.contains(event.relatedTarget)) {
      return;
    }

    showFor(anchor);
  });

  document.addEventListener("mouseout", (event) => {
    const anchor = anchorForEventTarget(event.target);

    if (!anchor || anchor.contains(event.relatedTarget)) {
      return;
    }

    scheduleHide();
  });

  document.addEventListener("focusin", (event) =>
    showFor(anchorForEventTarget(event.target)),
  );

  document.addEventListener("focusout", (event) => {
    if (anchorForEventTarget(event.target)) {
      scheduleHide();
    }
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      hideTooltip();
    }
  });

  window.addEventListener("scroll", hideTooltip, true);
  window.addEventListener("resize", () => positionTooltip(activeAnchor));
}
