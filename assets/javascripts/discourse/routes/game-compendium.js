import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

export default class GameCompendiumRoute extends Route {
  model() {
    return ajax("/game-compendium/assets", { data: { limit: 60 } }).catch((error) => ({
      assets: [],
      asset_groups: [],
      forbidden: error?.jqXHR?.status === 403,
    }));
  }
}
