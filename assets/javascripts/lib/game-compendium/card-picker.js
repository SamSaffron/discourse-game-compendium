import { swallowAutocompleteEvent } from "./autocomplete";
import {
  appendCardRowContent,
  autocompleteOptions,
  loadCards,
  searchCards,
} from "./cards";

export function openCardPicker(toolbarEvent) {
  const overlay = document.createElement("div");
  overlay.className = "game-compendium-card-picker-backdrop";
  overlay.innerHTML = `<div class="game-compendium-card-picker" role="dialog" aria-modal="true"><div class="game-compendium-card-picker-title">Insert game asset</div><input class="game-compendium-card-picker-input" placeholder="Search assets" autofocus><div class="game-compendium-card-picker-results"></div><div class="game-compendium-card-picker-help">Enter/click inserts <code>[[Asset]]</code>. Put it alone on a line for a full-size asset.</div></div>`;
  document.body.appendChild(overlay);

  const input = overlay.querySelector("input");
  const results = overlay.querySelector(".game-compendium-card-picker-results");
  let current = [];
  let selected = 0;

  const close = () => overlay.remove();
  const insert = (option) => {
    toolbarEvent.addText(`[[${option.card.name}]]`);
    close();
  };
  const render = async () => {
    const cards = searchCards(await loadCards(), input.value);
    current = autocompleteOptions(cards);
    selected = Math.min(selected, Math.max(0, current.length - 1));
    results.replaceChildren();

    current.forEach((option, index) => {
      const card = option.card;
      const row = document.createElement("button");
      row.type = "button";
      row.className = `game-compendium-card-picker-row ${index === selected ? "is-selected" : ""}`;
      appendCardRowContent(row, card);
      row.addEventListener("click", () => insert(option));
      results.appendChild(row);
    });
  };

  input.addEventListener("input", render);
  input.addEventListener("keydown", (event) => {
    if (
      !["Escape", "ArrowDown", "ArrowUp", "Enter", "Tab"].includes(event.key)
    ) {
      return;
    }

    swallowAutocompleteEvent(event);

    if (event.key === "Escape") {
      close();
    }

    if (event.key === "ArrowDown") {
      selected = Math.min(selected + 1, current.length - 1);
      render();
    }

    if (event.key === "ArrowUp") {
      selected = Math.max(selected - 1, 0);
      render();
    }

    if ((event.key === "Enter" || event.key === "Tab") && current[selected]) {
      insert(current[selected]);
    }
  });
  overlay.addEventListener("mousedown", (event) => {
    if (event.target === overlay) {
      close();
    }
  });

  render();
  setTimeout(() => input.focus(), 0);
}
