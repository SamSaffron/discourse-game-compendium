import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";
import { installComposerIntegrations } from "../../lib/game-compendium/composer";
import {
  decorateCompendium,
  installGlobalTooltipListeners,
} from "../../lib/game-compendium/tooltips";
import richEditorExtension from "../../lib/rich-editor-extension";

export default {
  name: "game-compendium",
  initialize() {
    withPluginApi((api) => {
      const siteSettings = api.container.lookup("service:site-settings");

      if (!siteSettings.game_compendium_enabled) {
        return;
      }

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
        true,
      );

      api.decorateCookedElement(decorateCompendium, { id: "game-compendium" });
      api.registerRichEditorExtension(richEditorExtension);
      installGlobalTooltipListeners();
      installComposerIntegrations(api);
    });
  },
};
