import {
  appendCardRowContent,
  autocompleteOptions,
  loadCards,
  searchCards,
} from "./cards";

let autocompletePortal;
let activeAutocompleteContext;
let autocompleteSeq = 0;

export function swallowAutocompleteEvent(event) {
  event.preventDefault();
  event.stopPropagation();
  event.stopImmediatePropagation();
}

function ensureAutocomplete() {
  if (autocompletePortal) {
    return autocompletePortal;
  }

  autocompletePortal = document.createElement("div");
  autocompletePortal.className = "game-compendium-autocomplete-portal";
  autocompletePortal.hidden = true;
  document.body.appendChild(autocompletePortal);

  return autocompletePortal;
}

function hideAutocomplete() {
  activeAutocompleteContext = null;

  if (autocompletePortal) {
    autocompletePortal.hidden = true;
    autocompletePortal.replaceChildren();
  }
}

function insertTextAtTextarea(textarea, start, end, text) {
  textarea.focus();
  textarea.setSelectionRange(start, end);
  document.execCommand("insertText", false, text);
  textarea.dispatchEvent(new Event("input", { bubbles: true }));
}

function insertTextAtContentEditable(range, text) {
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);
  document.execCommand("insertText", false, text);
}

function insertAutocompleteCard(asset, mode = "inline") {
  void mode;

  const ctx = activeAutocompleteContext;

  if (!ctx) {
    return;
  }

  const text = `[[${asset.name}]]`;

  if (ctx.type === "textarea") {
    insertTextAtTextarea(ctx.el, ctx.start, ctx.end, text);
  } else if (ctx.type === "contenteditable") {
    insertTextAtContentEditable(ctx.range, text);
  }

  hideAutocomplete();
}

function positionAutocomplete(anchorRect) {
  const box = ensureAutocomplete();
  const margin = 8;
  const rect = box.getBoundingClientRect();
  let left = anchorRect.left;
  let top = anchorRect.bottom + 6;

  if (left + rect.width > window.innerWidth - margin) {
    left = window.innerWidth - rect.width - margin;
  }

  if (top + rect.height > window.innerHeight - margin) {
    top = anchorRect.top - rect.height - 6;
  }

  box.style.left = `${Math.max(margin, Math.round(left))}px`;
  box.style.top = `${Math.max(margin, Math.round(top))}px`;
}

function renderAutocomplete(cards, query, anchorRect, mode = "inline") {
  const box = ensureAutocomplete();
  box.replaceChildren();

  const header = document.createElement("div");
  header.className = "game-compendium-autocomplete-header";
  header.textContent = mode === "block" ? "Insert asset block" : "Insert asset";
  box.appendChild(header);

  if (!cards.length) {
    const empty = document.createElement("div");
    empty.className = "game-compendium-autocomplete-empty";
    empty.textContent = `No assets matching "${query}"`;
    box.appendChild(empty);
  }

  const options = autocompleteOptions(cards);

  options.forEach(({ card }, index) => {
    const row = document.createElement("button");
    row.type = "button";
    row.className = "game-compendium-autocomplete-row";

    if (index === 0) {
      row.classList.add("is-selected");
    }

    appendCardRowContent(row, card);
    row.addEventListener("mousedown", (event) => {
      event.preventDefault();
      insertAutocompleteCard(card, mode);
    });
    box.appendChild(row);
  });

  box.hidden = false;
  requestAnimationFrame(() => positionAutocomplete(anchorRect));
}

async function maybeShowTextareaAutocomplete(textarea) {
  const seq = ++autocompleteSeq;
  const caret = textarea.selectionStart;
  const before = textarea.value.slice(0, caret);
  const match = before.match(/\[\[([^\]\n]{0,40})$/);

  if (!match) {
    hideAutocomplete();
    return;
  }

  const query = match[1];
  activeAutocompleteContext = {
    type: "textarea",
    el: textarea,
    start: caret - match[0].length,
    end: caret,
  };

  const cards = searchCards(await loadCards(), query);

  if (
    seq !== autocompleteSeq ||
    textarea.selectionStart !== caret ||
    textarea.value.slice(0, caret).slice(-match[0].length) !== match[0]
  ) {
    return;
  }

  const rect = textarea.getBoundingClientRect();
  renderAutocomplete(
    cards,
    query,
    {
      left: rect.left + 20,
      right: rect.left + 20,
      top: rect.top + 24,
      bottom: rect.top + 24,
    },
    "inline",
  );
}

async function maybeShowRichAutocomplete(root) {
  const seq = ++autocompleteSeq;
  const sel = window.getSelection();

  if (
    !sel?.rangeCount ||
    !root.contains(sel.anchorNode) ||
    sel.anchorNode.nodeType !== Node.TEXT_NODE
  ) {
    hideAutocomplete();
    return;
  }

  const text = sel.anchorNode.nodeValue.slice(0, sel.anchorOffset);
  const match = text.match(/\[\[([^\]\n]{0,40})$/);

  if (!match) {
    hideAutocomplete();
    return;
  }

  const range = sel.getRangeAt(0).cloneRange();
  range.setStart(sel.anchorNode, sel.anchorOffset - match[0].length);
  range.setEnd(sel.anchorNode, sel.anchorOffset);
  activeAutocompleteContext = { type: "contenteditable", range };

  const cards = searchCards(await loadCards(), match[1]);

  if (seq !== autocompleteSeq) {
    return;
  }

  const rect = range.getBoundingClientRect();
  renderAutocomplete(
    cards,
    match[1],
    rect.width ? rect : root.getBoundingClientRect(),
    "inline",
  );
}

function updateAutocomplete(event) {
  const target = event.target;

  if (
    target instanceof HTMLTextAreaElement &&
    target.classList.contains("d-editor-input")
  ) {
    maybeShowTextareaAutocomplete(target);
  } else if (target instanceof Element && target.closest(".ProseMirror")) {
    maybeShowRichAutocomplete(target.closest(".ProseMirror"));
  }
}

function moveAutocompleteSelection(event) {
  if (
    !autocompletePortal ||
    autocompletePortal.hidden ||
    !["Escape", "ArrowDown", "ArrowUp", "Enter", "Tab"].includes(event.key)
  ) {
    return;
  }

  swallowAutocompleteEvent(event);

  const rows = [
    ...autocompletePortal.querySelectorAll(".game-compendium-autocomplete-row"),
  ];
  let selected = rows.findIndex((r) => r.classList.contains("is-selected"));

  if (selected < 0) {
    selected = 0;
  }

  if (event.key === "Escape") {
    hideAutocomplete();
  }

  if (event.key === "ArrowDown") {
    rows[selected]?.classList.remove("is-selected");
    selected = Math.min(selected + 1, rows.length - 1);
    rows[selected]?.classList.add("is-selected");
  }

  if (event.key === "ArrowUp") {
    rows[selected]?.classList.remove("is-selected");
    selected = Math.max(selected - 1, 0);
    rows[selected]?.classList.add("is-selected");
  }

  if ((event.key === "Enter" || event.key === "Tab") && rows[selected]) {
    rows[selected].dispatchEvent(
      new MouseEvent("mousedown", { bubbles: true, cancelable: true }),
    );
  }
}

export function installAutocompleteListeners() {
  document.addEventListener("input", updateAutocomplete);
  document.addEventListener("keyup", (event) => {
    if (["ArrowUp", "ArrowDown", "Enter", "Escape"].includes(event.key)) {
      return;
    }

    updateAutocomplete(event);
  });
  document.addEventListener("keydown", moveAutocompleteSelection, true);
  document.addEventListener("mousedown", (event) => {
    if (
      autocompletePortal &&
      !autocompletePortal.hidden &&
      !autocompletePortal.contains(event.target)
    ) {
      hideAutocomplete();
    }
  });
}
