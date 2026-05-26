import { installAutocompleteListeners } from "./autocomplete";
import { openCardPicker } from "./card-picker";

export function installComposerIntegrations(api) {
  api.addComposerToolbarPopupMenuOption({
    name: "game-compendium-card",
    icon: "rectangle-list",
    label: "game_compendium.composer.insert_asset",
    action: openCardPicker,
  });

  installAutocompleteListeners();
}
