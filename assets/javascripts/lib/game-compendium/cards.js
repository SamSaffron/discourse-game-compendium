let cardIndexPromise;

export function slugify(name) {
  return name
    .toLowerCase()
    .replace(/['']/g, "")
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

export async function loadCards() {
  if (!cardIndexPromise) {
    cardIndexPromise = fetch("/game-compendium/asset-data.json")
      .then((response) => response.json())
      .then((payload) =>
        payload.assets.sort((a, b) => a.name.localeCompare(b.name)),
      );
  }

  return cardIndexPromise;
}

export function cardImageUrl(card) {
  return card.image;
}

export function appendCardRowContent(row, card) {
  const image = document.createElement("img");
  image.src = cardImageUrl(card);
  image.alt = "";

  const text = document.createElement("span");
  const name = document.createElement("strong");
  name.textContent = card.name;

  const details = document.createElement("small");
  details.textContent = card.asset_group || "";

  text.append(name, details);
  row.append(image, text);
}

export function searchCards(cards, query) {
  const q = query.trim().toLowerCase();
  if (!q) {
    return cards.slice(0, 12);
  }

  return cards
    .map((card) => {
      const name = card.name.toLowerCase();
      let score = 1000;

      if (name === q) {
        score = 0;
      } else if (name.startsWith(q)) {
        score = 1;
      } else {
        const idx = name.indexOf(q);
        if (idx >= 0) {
          score = 10 + idx;
        }
      }

      return { card, score };
    })
    .filter((x) => x.score < 1000)
    .sort((a, b) => a.score - b.score || a.card.name.localeCompare(b.card.name))
    .slice(0, 12)
    .map((x) => x.card);
}

export function autocompleteOptions(cards, limit = 6) {
  return cards.slice(0, limit).map((card) => ({ card }));
}
