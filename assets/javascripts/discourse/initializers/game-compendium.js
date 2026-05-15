import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";
import richEditorExtension from "../../lib/rich-editor-extension";

let tooltip; let activeAnchor; let hideTimer; let listenersInstalled = false;
function ensureTooltip() { if (tooltip) { return tooltip; } tooltip = document.createElement("div"); tooltip.className = "game-compendium-hover-portal"; tooltip.setAttribute("role", "tooltip"); tooltip.hidden = true; document.body.appendChild(tooltip); return tooltip; }
function clearHideTimer() { if (hideTimer) { clearTimeout(hideTimer); hideTimer = null; } }
function hideTooltip() { clearHideTimer(); activeAnchor = null; if (tooltip) { tooltip.hidden = true; tooltip.replaceChildren(); } }
function scheduleHide() { clearHideTimer(); hideTimer = setTimeout(hideTooltip, 80); }
function clamp(value, min, max) { return Math.max(min, Math.min(max, value)); }
function positionTooltip(anchor) { if (!tooltip || tooltip.hidden || !anchor) { return; } const rect = anchor.getBoundingClientRect(); const tipRect = tooltip.getBoundingClientRect(); const gap = 10; const margin = 8; let left = rect.left + rect.width / 2 - tipRect.width / 2; left = clamp(left, margin, window.innerWidth - tipRect.width - margin); const preferBelow = tooltip.classList.contains("game-compendium-hover-portal--below"); let top = preferBelow ? rect.bottom + gap : rect.top - tipRect.height - gap; if (preferBelow && top + tipRect.height > window.innerHeight - margin) { top = rect.top - tipRect.height - gap; } else if (!preferBelow && top < margin) { top = rect.bottom + gap; } top = clamp(top, margin, window.innerHeight - tipRect.height - margin); tooltip.style.left = `${Math.round(left)}px`; tooltip.style.top = `${Math.round(top)}px`; }
function slugify(name) { return name.toLowerCase().replace(/['']/g, '').replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, ''); }
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
  if (anchor.matches(".game-compendium-pm-card-ref, .game-compendium-pm-block-ref")) {
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
function showCardTooltip(anchor) {
  const imgData = cardImageFrom(anchor);
  if (!imgData?.src) {
    return;
  }
  clearHideTimer();
  activeAnchor = anchor;
  const tip = ensureTooltip();
  tip.classList.remove(
    "game-compendium-hover-portal--below",
    "game-compendium-hover-portal--card",
    "game-compendium-hover-portal--term"
  );
  tip.classList.add("game-compendium-hover-portal--card");
  tip.replaceChildren();
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
  const tip = ensureTooltip();
  tip.classList.remove("game-compendium-hover-portal--card", "game-compendium-hover-portal--term");
  tip.classList.add("game-compendium-hover-portal--below");
  tip.replaceChildren();
  const descriptionEl = document.createElement("div");
  descriptionEl.className = "game-compendium-hover-portal__card-description";
  descriptionEl.textContent = description;
  tip.appendChild(descriptionEl);
  tip.hidden = false;
  requestAnimationFrame(() => positionTooltip(anchor));
}
function showTermTooltip(anchor) { const source = anchor.querySelector(".game-compendium-term-tooltip"); if (!source) { return; } clearHideTimer(); activeAnchor = anchor; const tip = ensureTooltip(); tip.classList.remove("game-compendium-hover-portal--below", "game-compendium-hover-portal--card"); tip.classList.add("game-compendium-hover-portal--term"); tip.replaceChildren(source.cloneNode(true)); tip.hidden = false; requestAnimationFrame(() => positionTooltip(anchor)); }
function anchorForEventTarget(target) { if (!(target instanceof Element)) { return null; } return target.closest(".game-compendium-card-ref, .game-compendium-card-block, .game-compendium-term-ref, .game-compendium-pm-card-ref, .game-compendium-pm-block-ref"); }
function showFor(anchor) { if (!anchor) { return; } if (anchor.matches(".game-compendium-card-block")) { showCardDescriptionTooltip(anchor); } else if (anchor.matches(".game-compendium-card-ref, .game-compendium-pm-card-ref, .game-compendium-pm-block-ref")) { showCardTooltip(anchor); } else if (anchor.matches(".game-compendium-term-ref")) { showTermTooltip(anchor); } }
function installGlobalTooltipListeners() { if (listenersInstalled) { return; } listenersInstalled = true; document.addEventListener("mouseover", (event) => { const anchor = anchorForEventTarget(event.target); if (!anchor || anchor.contains(event.relatedTarget)) { return; } showFor(anchor); }); document.addEventListener("mouseout", (event) => { const anchor = anchorForEventTarget(event.target); if (!anchor || anchor.contains(event.relatedTarget)) { return; } scheduleHide(); }); document.addEventListener("focusin", (event) => showFor(anchorForEventTarget(event.target))); document.addEventListener("focusout", (event) => { if (anchorForEventTarget(event.target)) { scheduleHide(); } }); document.addEventListener("keydown", (event) => { if (event.key === "Escape") { hideTooltip(); } }); window.addEventListener("scroll", hideTooltip, true); window.addEventListener("resize", () => positionTooltip(activeAnchor)); }
function decorateCompendium(elem) {
  elem
    .querySelectorAll(".game-compendium-ref, .game-compendium-card-block")
    .forEach((ref) => ref.setAttribute("data-game-compendium-tooltip-ready", "true"));

  enrichCompendiumDescriptions(elem);
}

let cardIndexPromise;
let autocompletePortal;
let activeAutocompleteContext;
let autocompleteSeq = 0;

async function loadCards() {
  if (!cardIndexPromise) {
    cardIndexPromise = fetch("/game-compendium/asset-data.json")
      .then((response) => response.json())
      .then((payload) => payload.assets.sort((a, b) => a.name.localeCompare(b.name)));
  }
  return cardIndexPromise;
}

async function enrichCompendiumDescriptions(elem) {
  const refs = [...elem.querySelectorAll(".game-compendium-card-ref, .game-compendium-card-block")];
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
function cardImageUrl(card) { return card.image; }
function appendCardRowContent(row, card) { const image = document.createElement("img"); image.src = cardImageUrl(card); image.alt = ""; const text = document.createElement("span"); const name = document.createElement("strong"); name.textContent = card.name; const details = document.createElement("small"); details.textContent = card.asset_group || ""; text.append(name, details); row.append(image, text); }
function searchCards(cards, query) {
  const q = query.trim().toLowerCase();
  if (!q) { return cards.slice(0, 12); }
  return cards.map((card) => { const name = card.name.toLowerCase(); let score = 1000; if (name === q) { score = 0; } else if (name.startsWith(q)) { score = 1; } else { const idx = name.indexOf(q); if (idx >= 0) { score = 10 + idx; } } return { card, score }; }).filter((x) => x.score < 1000).sort((a, b) => a.score - b.score || a.card.name.localeCompare(b.card.name)).slice(0, 12).map((x) => x.card);
}
function autocompleteOptions(cards, limit = 6) {
  return cards.slice(0, limit).map((card) => ({ card }));
}
function ensureAutocomplete() { if (autocompletePortal) { return autocompletePortal; } autocompletePortal = document.createElement("div"); autocompletePortal.className = "game-compendium-autocomplete-portal"; autocompletePortal.hidden = true; document.body.appendChild(autocompletePortal); return autocompletePortal; }
function swallowAutocompleteEvent(event) { event.preventDefault(); event.stopPropagation(); event.stopImmediatePropagation(); }
function hideAutocomplete() { activeAutocompleteContext = null; if (autocompletePortal) { autocompletePortal.hidden = true; autocompletePortal.replaceChildren(); } }
function insertTextAtTextarea(textarea, start, end, text) { textarea.focus(); textarea.setSelectionRange(start, end); document.execCommand("insertText", false, text); textarea.dispatchEvent(new Event("input", { bubbles: true })); }
function insertTextAtContentEditable(range, text) { const sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(range); document.execCommand("insertText", false, text); }
function insertAutocompleteCard(asset, mode = "inline") { void mode; const ctx = activeAutocompleteContext; if (!ctx) { return; } const text = `[[${asset.name}]]`; if (ctx.type === "textarea") { insertTextAtTextarea(ctx.el, ctx.start, ctx.end, text); } else if (ctx.type === "contenteditable") { insertTextAtContentEditable(ctx.range, text); } hideAutocomplete(); }
function positionAutocomplete(anchorRect) { const box = ensureAutocomplete(); const margin = 8; const rect = box.getBoundingClientRect(); let left = anchorRect.left; let top = anchorRect.bottom + 6; if (left + rect.width > window.innerWidth - margin) { left = window.innerWidth - rect.width - margin; } if (top + rect.height > window.innerHeight - margin) { top = anchorRect.top - rect.height - 6; } box.style.left = `${Math.max(margin, Math.round(left))}px`; box.style.top = `${Math.max(margin, Math.round(top))}px`; }
function renderAutocomplete(cards, query, anchorRect, mode = "inline") { const box = ensureAutocomplete(); box.replaceChildren(); const header = document.createElement("div"); header.className = "game-compendium-autocomplete-header"; header.textContent = mode === "block" ? "Insert asset block" : "Insert asset"; box.appendChild(header); if (!cards.length) { const empty = document.createElement("div"); empty.className = "game-compendium-autocomplete-empty"; empty.textContent = `No assets matching "${query}"`; box.appendChild(empty); } const options = autocompleteOptions(cards); options.forEach(({ card }, index) => { const row = document.createElement("button"); row.type = "button"; row.className = "game-compendium-autocomplete-row"; if (index === 0) { row.classList.add("is-selected"); } appendCardRowContent(row, card); row.addEventListener("mousedown", (event) => { event.preventDefault(); insertAutocompleteCard(card, mode); }); box.appendChild(row); }); box.hidden = false; requestAnimationFrame(() => positionAutocomplete(anchorRect)); }
async function maybeShowTextareaAutocomplete(textarea) { const seq = ++autocompleteSeq; const caret = textarea.selectionStart; const before = textarea.value.slice(0, caret); const match = before.match(/\[\[([^\]\n]{0,40})$/); if (!match) { hideAutocomplete(); return; } const query = match[1]; activeAutocompleteContext = { type: "textarea", el: textarea, start: caret - match[0].length, end: caret }; const cards = searchCards(await loadCards(), query); if (seq !== autocompleteSeq || textarea.selectionStart !== caret || textarea.value.slice(0, caret).slice(-match[0].length) !== match[0]) { return; } const rect = textarea.getBoundingClientRect(); renderAutocomplete(cards, query, { left: rect.left + 20, right: rect.left + 20, top: rect.top + 24, bottom: rect.top + 24 }, "inline"); }
async function maybeShowRichAutocomplete(root) { const seq = ++autocompleteSeq; const sel = window.getSelection(); if (!sel?.rangeCount || !root.contains(sel.anchorNode) || sel.anchorNode.nodeType !== Node.TEXT_NODE) { hideAutocomplete(); return; } const text = sel.anchorNode.nodeValue.slice(0, sel.anchorOffset); const match = text.match(/\[\[([^\]\n]{0,40})$/); if (!match) { hideAutocomplete(); return; } const range = sel.getRangeAt(0).cloneRange(); range.setStart(sel.anchorNode, sel.anchorOffset - match[0].length); range.setEnd(sel.anchorNode, sel.anchorOffset); activeAutocompleteContext = { type: "contenteditable", range }; const cards = searchCards(await loadCards(), match[1]); if (seq !== autocompleteSeq) { return; } const rect = range.getBoundingClientRect(); renderAutocomplete(cards, match[1], rect.width ? rect : root.getBoundingClientRect(), "inline"); }
function openCardPicker(toolbarEvent) { const overlay = document.createElement("div"); overlay.className = "game-compendium-card-picker-backdrop"; overlay.innerHTML = `<div class="game-compendium-card-picker" role="dialog" aria-modal="true"><div class="game-compendium-card-picker-title">Insert game asset</div><input class="game-compendium-card-picker-input" placeholder="Search assets" autofocus><div class="game-compendium-card-picker-results"></div><div class="game-compendium-card-picker-help">Enter/click inserts <code>[[Asset]]</code>. Put it alone on a line for a full-size asset.</div></div>`; document.body.appendChild(overlay); const input = overlay.querySelector("input"); const results = overlay.querySelector(".game-compendium-card-picker-results"); let current = []; let selected = 0; const close = () => overlay.remove(); const insert = (option) => { toolbarEvent.addText(`[[${option.card.name}]]`); close(); }; const render = async () => { const cards = searchCards(await loadCards(), input.value); current = autocompleteOptions(cards); selected = Math.min(selected, Math.max(0, current.length - 1)); results.replaceChildren(); current.forEach((option, index) => { const card = option.card; const row = document.createElement("button"); row.type = "button"; row.className = `game-compendium-card-picker-row ${index === selected ? "is-selected" : ""}`; appendCardRowContent(row, card); row.addEventListener("click", () => insert(option)); results.appendChild(row); }); }; input.addEventListener("input", render); input.addEventListener("keydown", (event) => { if (!["Escape", "ArrowDown", "ArrowUp", "Enter", "Tab"].includes(event.key)) { return; } swallowAutocompleteEvent(event); if (event.key === "Escape") { close(); } if (event.key === "ArrowDown") { selected = Math.min(selected + 1, current.length - 1); render(); } if (event.key === "ArrowUp") { selected = Math.max(selected - 1, 0); render(); } if ((event.key === "Enter" || event.key === "Tab") && current[selected]) { insert(current[selected]); } }); overlay.addEventListener("mousedown", (event) => { if (event.target === overlay) { close(); } }); render(); setTimeout(() => input.focus(), 0); }
function installDiscovery(api) { api.addComposerToolbarPopupMenuOption({ name: "game-compendium-card", icon: "rectangle-list", label: "game_compendium.composer.insert_asset", action: openCardPicker }); document.addEventListener("input", (event) => { const target = event.target; if (target instanceof HTMLTextAreaElement && target.classList.contains("d-editor-input")) { maybeShowTextareaAutocomplete(target); } else if (target instanceof Element && target.closest(".ProseMirror")) { maybeShowRichAutocomplete(target.closest(".ProseMirror")); } }); document.addEventListener("keyup", (event) => { if (["ArrowUp", "ArrowDown", "Enter", "Escape"].includes(event.key)) { return; } const target = event.target; if (target instanceof HTMLTextAreaElement && target.classList.contains("d-editor-input")) { maybeShowTextareaAutocomplete(target); } else if (target instanceof Element && target.closest(".ProseMirror")) { maybeShowRichAutocomplete(target.closest(".ProseMirror")); } }); document.addEventListener("keydown", (event) => { if (!autocompletePortal || autocompletePortal.hidden || !["Escape", "ArrowDown", "ArrowUp", "Enter", "Tab"].includes(event.key)) { return; } swallowAutocompleteEvent(event); const rows = [...autocompletePortal.querySelectorAll(".game-compendium-autocomplete-row")]; let selected = rows.findIndex((r) => r.classList.contains("is-selected")); if (selected < 0) { selected = 0; } if (event.key === "Escape") { hideAutocomplete(); } if (event.key === "ArrowDown") { rows[selected]?.classList.remove("is-selected"); selected = Math.min(selected + 1, rows.length - 1); rows[selected]?.classList.add("is-selected"); } if (event.key === "ArrowUp") { rows[selected]?.classList.remove("is-selected"); selected = Math.max(selected - 1, 0); rows[selected]?.classList.add("is-selected"); } if ((event.key === "Enter" || event.key === "Tab") && rows[selected]) { rows[selected].dispatchEvent(new MouseEvent("mousedown", { bubbles: true, cancelable: true })); } }, true); document.addEventListener("mousedown", (event) => { if (autocompletePortal && !autocompletePortal.hidden && !autocompletePortal.contains(event.target)) { hideAutocomplete(); } }); }

export default {
  name: "game-compendium",
  initialize() {
    withPluginApi((api) => {
      const siteSettings = api.container.lookup("service:site-settings");
      if (!siteSettings.game_compendium_enabled) { return; }
      api.addCommunitySectionLink(
        (baseSectionLink) =>
          class GameCompendiumSectionLink extends baseSectionLink {
            name = "game-compendium";
            href = "/game-compendium";
            text = i18n("game_compendium.sidebar_label");
            title = i18n("game_compendium.sidebar_label");
            defaultPrefixValue = "rectangle-list";

            get shouldDisplay() {
              return this.currentUser?.can_manage_game_compendium_assets;
            }
          },
        true
      );
      api.decorateCookedElement(decorateCompendium, { id: "game-compendium" });
      api.registerRichEditorExtension(richEditorExtension);
      installGlobalTooltipListeners();
      installDiscovery(api);
    });
  },
};
