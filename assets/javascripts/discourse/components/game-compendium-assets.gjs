import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

const PAGE_SIZE = 60;
const VALID_TABS = new Set(["browse", "upload", "asset_groups"]);

export default class GameCompendiumAssets extends Component {
  @service dialog;
  @service toasts;

  @tracked activeTab = "browse";
  @tracked message = "";
  @tracked uploading = false;
  @tracked saving = false;
  @tracked deleting = false;
  @tracked creatingAssetGroup = false;
  @tracked deletingAssetGroupSlug = null;
  @tracked selected = null;
  @tracked replacementFile = null;
  @tracked replacementPreviewUrl = null;
  @tracked editSlug = "";
  @tracked editAssetGroup = "";
  @tracked editDescription = "";
  @tracked filter = "";
  @tracked asset_groupFilter = "";
  @tracked assets = [];
  @tracked offset = 0;
  @tracked total = 0;
  @tracked hasMore = false;
  @tracked loading = false;
  @tracked asset_groups = [];
  @tracked newAssetGroupSlug = "";
  @tracked newAssetGroupName = "";
  @tracked selectedSlugs = [];
  @tracked selectAllMatching = false;
  @tracked bulkAssetGroup = "";
  @tracked bulkOperating = false;
  @tracked bulkSelectionMode = false;
  loadSeq = 0;

  constructor() {
    super(...arguments);
    this.asset_groups = this.args.asset_groups || [];
    this.assets = this.annotateAssets(this.args.assets || []);
    this.total = this.args.total || this.assets.length;
    this.offset = this.assets.length;
    this.hasMore = !!this.args.hasMore;
    const urlTab = new URLSearchParams(window.location.search).get("tab");
    if (VALID_TABS.has(urlTab)) {
      this.activeTab = urlTab;
    }
  }

  willDestroy() {
    super.willDestroy(...arguments);
    this.revokeReplacementPreview();
  }

  get uploadAssetGroupOptions() {
    return [
      { slug: "", name: i18n("game_compendium.no_asset_group") },
      ...this.asset_groups,
    ];
  }

  get previewUrl() {
    return this.replacementPreviewUrl || this.selected?.url;
  }

  get selectedCount() {
    return this.selectAllMatching ? this.total : this.selectedSlugs.length;
  }

  get hasSelection() {
    return this.selectedCount > 0;
  }

  get allVisibleSelected() {
    return (
      this.assets.length > 0 && this.assets.every((asset) => asset.selected)
    );
  }

  get bulkAssetGroupOptions() {
    return [
      { slug: "", name: i18n("game_compendium.no_asset_group") },
      ...this.asset_groups,
    ];
  }

  toast(message) {
    this.toasts.success({
      duration: "short",
      data: { message },
    });
  }

  annotateAssets(assets) {
    const selected = new Set(this.selectedSlugs);
    return assets.map((asset) => ({
      ...asset,
      selected: this.selectAllMatching || selected.has(asset.slug),
    }));
  }

  clearSelection() {
    this.selectedSlugs = [];
    this.selectAllMatching = false;
  }

  bulkPayload() {
    if (this.selectAllMatching) {
      return {
        all_matching: true,
        q: this.filter,
        filter_asset_group: this.asset_groupFilter,
      };
    }

    return { slugs: this.selectedSlugs };
  }

  revokeReplacementPreview() {
    if (this.replacementPreviewUrl) {
      URL.revokeObjectURL(this.replacementPreviewUrl);
      this.replacementPreviewUrl = null;
    }
  }

  @action
  switchTab(tab, event) {
    event?.preventDefault();
    this.activeTab = tab;
    this.message = "";
    this.selected = null;
    this.clearSelection();
    if (tab === "browse" && !this.args.forbidden && this.assets.length === 0) {
      this.loadAssets({ reset: true });
    }
    const url = new URL(window.location.href);
    if (tab === "browse") {
      url.searchParams.delete("tab");
    } else {
      url.searchParams.set("tab", tab);
    }
    window.history.replaceState({}, "", url);
  }

  @action
  updateFilter(event) {
    this.filter = event.target.value;
    this.clearSelection();
    this.loadAssets({ reset: true });
  }

  @action
  updateAssetGroupFilter(event) {
    this.asset_groupFilter = event.target.value;
    this.clearSelection();
    this.loadAssets({ reset: true });
  }

  @action
  maybeLoadMore(event) {
    const el = event.target;
    if (el.scrollTop + el.clientHeight >= el.scrollHeight - 260) {
      this.loadMore();
    }
  }

  @action
  loadMore(event) {
    event?.preventDefault();
    this.loadAssets();
  }

  async loadAssets({ reset = false } = {}) {
    if (this.loading && !reset) {
      return;
    }

    const offset = reset ? 0 : this.offset;
    const requestSeq = ++this.loadSeq;
    const requestFilter = this.filter;
    const requestAssetGroupFilter = this.asset_groupFilter;
    this.loading = true;
    if (reset) {
      this.assets = [];
      this.offset = 0;
      this.total = 0;
      this.hasMore = false;
    }

    try {
      const data = await ajax("/game-compendium/assets", {
        data: {
          q: requestFilter,
          asset_group: requestAssetGroupFilter,
          offset,
          limit: PAGE_SIZE,
        },
      });
      if (
        requestSeq !== this.loadSeq ||
        requestFilter !== this.filter ||
        requestAssetGroupFilter !== this.asset_groupFilter
      ) {
        return;
      }

      const incoming = this.annotateAssets(data.assets || []);
      this.assets = reset ? incoming : [...this.assets, ...incoming];
      this.offset = offset + incoming.length;
      this.total = data.total || 0;
      this.hasMore = !!data.has_more;
      this.asset_groups = data.asset_groups || this.asset_groups;
    } catch (error) {
      popupAjaxError(error);
    } finally {
      if (requestSeq === this.loadSeq) {
        this.loading = false;
      }
    }
  }

  @action
  openAsset(asset, event) {
    event?.preventDefault();
    this.revokeReplacementPreview();
    this.selected = asset;
    this.editSlug = asset.slug;
    this.editAssetGroup = asset.asset_group || "";
    this.editDescription = asset.description || "";
    this.replacementFile = null;
    this.message = "";
  }

  @action
  closeAsset(event) {
    event?.preventDefault();
    this.selected = null;
    this.replacementFile = null;
    this.revokeReplacementPreview();
  }

  @action
  updateEditSlug(event) {
    this.editSlug = event.target.value;
  }

  @action
  updateEditAssetGroup(event) {
    this.editAssetGroup = event.target.value;
  }

  @action
  updateEditDescription(event) {
    this.editDescription = event.target.value;
  }

  @action
  setReplacementFile(event) {
    this.revokeReplacementPreview();
    this.replacementFile = event.target.files?.[0] || null;
    if (this.replacementFile) {
      this.replacementPreviewUrl = URL.createObjectURL(this.replacementFile);
    }
  }

  @action
  clearReplacementFile(event) {
    event?.preventDefault();
    this.replacementFile = null;
    this.revokeReplacementPreview();
    const input = event?.target
      ?.closest("form")
      ?.querySelector(".game-compendium-replacement-input");
    if (input) {
      input.value = "";
    }
  }

  @action
  updateNewAssetGroupSlug(event) {
    this.newAssetGroupSlug = event.target.value;
  }

  @action
  updateNewAssetGroupName(event) {
    this.newAssetGroupName = event.target.value;
  }

  @action
  enableBulkSelection(event) {
    event?.preventDefault();
    this.bulkSelectionMode = true;
  }

  @action
  selectAllVisible(event) {
    event?.preventDefault();
    const selected = new Set(this.selectedSlugs);
    this.assets.forEach((asset) => selected.add(asset.slug));
    this.selectedSlugs = [...selected];
    this.assets = this.annotateAssets(this.assets);
  }

  @action
  toggleAssetSelection(asset, event) {
    event?.stopPropagation();
    const checked = event?.target?.checked;
    const selected = new Set(this.selectedSlugs);

    if (checked) {
      selected.add(asset.slug);
    } else {
      selected.delete(asset.slug);
      this.selectAllMatching = false;
    }

    this.selectedSlugs = [...selected];
    this.assets = this.annotateAssets(this.assets);
  }

  @action
  toggleSelectVisible(event) {
    const checked = event.target.checked;
    const selected = new Set(this.selectedSlugs);

    this.assets.forEach((asset) => {
      if (checked) {
        selected.add(asset.slug);
      } else {
        selected.delete(asset.slug);
      }
    });

    if (!checked) {
      this.selectAllMatching = false;
    }

    this.selectedSlugs = [...selected];
    this.assets = this.annotateAssets(this.assets);
  }

  @action
  selectEveryMatchingAsset(event) {
    event?.preventDefault();
    this.selectAllMatching = true;
    this.selectedSlugs = this.assets.map((asset) => asset.slug);
    this.assets = this.annotateAssets(this.assets);
  }

  @action
  clearBulkSelection(event) {
    event?.preventDefault();
    this.clearSelection();
    this.bulkSelectionMode = false;
    this.assets = this.annotateAssets(this.assets);
  }

  @action
  updateBulkAssetGroup(event) {
    this.bulkAssetGroup = event.target.value;
  }

  @action
  bulkDeleteAssets(event) {
    event?.preventDefault();
    if (!this.hasSelection || this.loading) {
      return;
    }

    this.dialog.confirm({
      message: i18n("game_compendium.confirm_bulk_delete_assets", {
        count: this.selectedCount,
      }),
      didConfirm: async () => {
        this.bulkOperating = true;
        this.message = "";
        try {
          const result = await ajax("/game-compendium/assets/bulk", {
            type: "DELETE",
            data: this.bulkPayload(),
          });
          this.toast(
            i18n("game_compendium.messages.deleted_assets", {
              count: result.deleted || 0,
            })
          );
          this.clearSelection();
          this.bulkSelectionMode = false;
          await this.loadAssets({ reset: true });
        } catch (error) {
          popupAjaxError(error);
        } finally {
          this.bulkOperating = false;
        }
      },
    });
  }

  @action
  async bulkSetAssetGroup(event) {
    event?.preventDefault();
    if (!this.hasSelection || this.loading) {
      return;
    }

    this.bulkOperating = true;
    this.message = "";
    try {
      const result = await ajax("/game-compendium/assets/bulk", {
        type: "PATCH",
        data: {
          ...this.bulkPayload(),
          asset_group: this.bulkAssetGroup,
        },
      });
      this.toast(
        i18n("game_compendium.messages.updated_assets", {
          count: result.updated || 0,
        })
      );
      this.clearSelection();
      this.bulkSelectionMode = false;
      await this.loadAssets({ reset: true });
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.bulkOperating = false;
    }
  }

  @action
  deleteAsset(event) {
    event?.preventDefault();
    if (!this.selected) {
      return;
    }

    const slug = this.selected.slug;
    this.dialog.confirm({
      message: i18n("game_compendium.confirm_delete_asset", { slug }),
      didConfirm: async () => {
        this.deleting = true;
        this.message = "";
        try {
          await ajax(`/game-compendium/assets/${slug}`, { type: "DELETE" });
          this.toast(i18n("game_compendium.messages.deleted_asset", { slug }));
          this.selected = null;
          this.revokeReplacementPreview();
          await this.loadAssets({ reset: true });
        } catch (error) {
          popupAjaxError(error);
        } finally {
          this.deleting = false;
        }
      },
    });
  }

  @action
  async saveAsset(event) {
    event.preventDefault();
    if (!this.selected) {
      return;
    }

    this.saving = true;
    this.message = "";
    const formData = new FormData();
    formData.append("slug", this.editSlug);
    formData.append("asset_group", this.editAssetGroup);
    formData.append("description", this.editDescription);
    if (this.replacementFile) {
      formData.append("file", this.replacementFile);
    }

    try {
      const result = await ajax(`/game-compendium/assets/${this.selected.slug}`, {
        type: "PATCH",
        data: formData,
        processData: false,
        contentType: false,
      });
      this.toast(i18n("game_compendium.messages.saved_asset", { slug: result.slug }));
      this.selected = result;
      this.editSlug = result.slug;
      this.editAssetGroup = result.asset_group || "";
      this.editDescription = result.description || "";
      this.replacementFile = null;
      this.revokeReplacementPreview();
      const replacementInput = event.target.querySelector(
        ".game-compendium-replacement-input"
      );
      if (replacementInput) {
        replacementInput.value = "";
      }
      await this.loadAssets({ reset: true });
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.saving = false;
    }
  }

  @action
  async uploadSingle(event) {
    event.preventDefault();
    const form = event.target;
    const formData = new FormData(form);
    const succeeded = await this.upload(formData, false);
    if (succeeded) {
      form.reset();
    }
  }

  @action
  async uploadBatch(event) {
    const form = event.target.form;
    const files = event.target.files;
    if (!files.length) {
      return;
    }

    const formData = new FormData();
    formData.append("asset_group", form.querySelector("[name=batch_asset_group]")?.value || "");
    for (const file of files) {
      formData.append("files[]", file);
    }

    const succeeded = await this.upload(formData, true);
    if (succeeded) {
      event.target.value = "";
    }
  }

  async upload(formData, batch) {
    this.uploading = true;
    this.message = "";
    try {
      const result = await ajax("/game-compendium/assets", {
        type: "POST",
        data: formData,
        processData: false,
        contentType: false,
      });
      if (batch) {
        const count = result.uploaded?.length || 0;
        const errors = result.errors || [];
        this.message =
          count > 0
            ? i18n("game_compendium.messages.uploaded_assets", { count })
            : i18n("game_compendium.messages.no_assets_uploaded");
        if (count > 0) {
          this.toast(i18n("game_compendium.messages.uploaded_assets", { count }));
        }
        if (errors.length) {
          this.message += ` ${i18n("game_compendium.messages.errors_prefix")}: ${errors.join("; ")}`;
        }
      } else {
        this.toast(i18n("game_compendium.messages.uploaded_asset", { slug: result.slug }));
      }
      await this.loadAssets({ reset: true });
      return true;
    } catch (error) {
      popupAjaxError(error);
      return false;
    } finally {
      this.uploading = false;
    }
  }

  @action
  async createAssetGroup(event) {
    event.preventDefault();
    this.message = "";
    this.creatingAssetGroup = true;
    try {
      const result = await ajax("/game-compendium/asset-groups", {
        type: "POST",
        data: { slug: this.newAssetGroupSlug, name: this.newAssetGroupName },
      });
      this.asset_groups = [...this.asset_groups, result.asset_group].sort((a, b) => a.name.localeCompare(b.name));
      this.newAssetGroupSlug = "";
      this.newAssetGroupName = "";
      event.target.reset();
      this.toast(i18n("game_compendium.messages.added_asset_group", { name: result.asset_group.name }));
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.creatingAssetGroup = false;
    }
  }

  @action
  deleteAssetGroup(asset_group, event) {
    event?.preventDefault();
    this.dialog.confirm({
      message: i18n("game_compendium.confirm_delete_asset_group", { name: asset_group.name }),
      didConfirm: async () => {
        this.message = "";
        this.deletingAssetGroupSlug = asset_group.slug;
        try {
          await ajax(`/game-compendium/asset-groups/${asset_group.slug}`, { type: "DELETE" });
          this.asset_groups = this.asset_groups.filter((item) => item.slug !== asset_group.slug);
          if (this.asset_groupFilter === asset_group.slug) {
            this.asset_groupFilter = "";
          }
          this.toast(i18n("game_compendium.messages.deleted_asset_group", { name: asset_group.name }));
          await this.loadAssets({ reset: true });
        } catch (error) {
          popupAjaxError(error);
        } finally {
          this.deletingAssetGroupSlug = null;
        }
      },
    });
  }

  <template>
    <div class="game-compendium-assets">
      <div class="wrap">
        <h2>{{i18n "game_compendium.title"}}</h2>
        <p class="game-compendium-intro">{{i18n "game_compendium.intro"}}</p>

        {{#if @forbidden}}
          <div class="alert alert-error">{{i18n "game_compendium.forbidden"}}</div>
        {{else}}
          <ul class="game-compendium-tabs nav-pills nav">
            <li class={{if (eq this.activeTab "browse") "active"}}><a href="#" {{on "click" (fn this.switchTab "browse")}}>{{i18n "game_compendium.tabs.browse"}}</a></li>
            <li class={{if (eq this.activeTab "upload") "active"}}><a href="#" {{on "click" (fn this.switchTab "upload")}}>{{i18n "game_compendium.tabs.upload"}}</a></li>
            <li class={{if (eq this.activeTab "asset_groups") "active"}}><a href="#" {{on "click" (fn this.switchTab "asset_groups")}}>{{i18n "game_compendium.tabs.asset_groups"}}</a></li>
          </ul>

          {{#if (eq this.activeTab "browse")}}
            <section class="game-compendium-section">
              <div class="game-compendium-toolbar">
                <h3>{{i18n "game_compendium.assets_heading"}} <span class="game-compendium-count">({{i18n "game_compendium.matching_count" count=this.total}})</span></h3>
                <label class="game-compendium-filter game-compendium-filter--asset-group">
                  <span>{{i18n "game_compendium.asset_group"}}</span>
                  <select value={{this.asset_groupFilter}} {{on "change" this.updateAssetGroupFilter}}>
                    <option value="" selected={{eq this.asset_groupFilter ""}}>{{i18n "game_compendium.all_asset_groups"}}</option>
                    <option value="__ungrouped" selected={{eq this.asset_groupFilter "__ungrouped"}}>{{i18n "game_compendium.ungrouped"}}</option>
                    {{#each this.asset_groups as |asset_group|}}
                      <option value={{asset_group.slug}} selected={{eq this.asset_groupFilter asset_group.slug}}>{{asset_group.name}}</option>
                    {{/each}}
                  </select>
                </label>
                <label class="game-compendium-filter game-compendium-filter--search">
                  <span>{{i18n "game_compendium.search_label"}}</span>
                  <input type="search" value={{this.filter}} placeholder={{i18n "game_compendium.search_placeholder"}} {{on "input" this.updateFilter}} />
                </label>
              </div>

              <div class="game-compendium-bulk-actions {{unless this.bulkSelectionMode "game-compendium-bulk-actions--inactive"}}">
                {{#if this.bulkSelectionMode}}
                  <div class="game-compendium-bulk-actions__row game-compendium-bulk-actions__row--selection">
                    <div class="game-compendium-bulk-actions__selection">
                      <DButton @label="game_compendium.select_all" @action={{this.selectAllVisible}} @disabled={{this.loading}} class="btn-small" />
                      <DButton @label="game_compendium.clear_all" @action={{this.clearBulkSelection}} @disabled={{this.bulkOperating}} class="btn-small" />
                    </div>
                    {{#if this.hasSelection}}
                      <div class="game-compendium-bulk-actions__summary">
                        <span class="game-compendium-bulk-actions__count">{{i18n "game_compendium.selected_count" count=this.selectedCount}}</span>
                      </div>
                    {{/if}}
                  </div>

                  {{#if this.hasSelection}}
                    {{#if this.hasMore}}
                      {{#unless this.selectAllMatching}}
                        <div class="game-compendium-bulk-actions__notice">
                          {{i18n "game_compendium.visible_selected" count=this.selectedSlugs.length}}
                          <button type="button" class="btn-link" disabled={{this.loading}} {{on "click" this.selectEveryMatchingAsset}}>{{i18n "game_compendium.select_all_matching" count=this.total}}</button>
                        </div>
                      {{/unless}}
                    {{/if}}

                    <div class="game-compendium-bulk-actions__row game-compendium-bulk-actions__row--operations">
                      <label class="game-compendium-bulk-actions__asset-group">
                        <span>{{i18n "game_compendium.bulk_set_asset_group"}}</span>
                        <select value={{this.bulkAssetGroup}} disabled={{this.bulkOperating}} {{on "change" this.updateBulkAssetGroup}}>
                          {{#each this.bulkAssetGroupOptions as |asset_group|}}<option value={{asset_group.slug}} selected={{eq this.bulkAssetGroup asset_group.slug}}>{{asset_group.name}}</option>{{/each}}
                        </select>
                      </label>
                      <div class="game-compendium-bulk-actions__operations">
                        <DButton @label="game_compendium.apply" @action={{this.bulkSetAssetGroup}} @isLoading={{this.bulkOperating}} @disabled={{if this.loading true this.bulkOperating}} class="btn-primary btn-small" />
                        <DButton @label="game_compendium.delete_selected" @action={{this.bulkDeleteAssets}} @isLoading={{this.bulkOperating}} @disabled={{if this.loading true this.bulkOperating}} class="btn-danger btn-small" />
                      </div>
                    </div>
                  {{/if}}
                {{else}}
                  <DButton @label="game_compendium.select" @action={{this.enableBulkSelection}} @disabled={{this.loading}} class="btn-small" />
                {{/if}}
              </div>

              <div class="game-compendium-card-grid" {{on "scroll" this.maybeLoadMore}}>
                {{#each this.assets as |asset|}}
                  <div class="game-compendium-card-item {{if asset.selected "is-selected"}}">
                    {{#if this.bulkSelectionMode}}
                      <label class="game-compendium-card-item__select">
                        <input type="checkbox" checked={{asset.selected}} aria-label={{i18n "game_compendium.select_asset" slug=asset.slug}} {{on "change" (fn this.toggleAssetSelection asset)}} />
                      </label>
                    {{/if}}
                    <button type="button" class="game-compendium-card-item__open" title={{asset.slug}} {{on "click" (fn this.openAsset asset)}}>
                      <img src={{asset.url}} alt={{asset.slug}} loading="lazy" />
                      <span class="game-compendium-card-slug">{{asset.slug}}</span>
                      {{#if asset.asset_group}}<span class="game-compendium-card-asset-group">{{asset.asset_group}}</span>{{/if}}
                    </button>
                  </div>
                {{/each}}
                {{#if this.loading}}<div class="game-compendium-loading">{{i18n "game_compendium.loading"}}</div>{{/if}}
              </div>

              {{#if this.hasMore}}
                <DButton @action={{this.loadMore}} @label="game_compendium.load_more" @isLoading={{this.loading}} @disabled={{this.loading}} />
              {{/if}}
            </section>
          {{/if}}

          {{#if (eq this.activeTab "upload")}}
            <section class="game-compendium-section game-compendium-upload-panel">
              <h3>{{i18n "game_compendium.upload_assets"}}</h3>
              <form class="game-compendium-upload" {{on "submit" this.uploadSingle}}>
                <h4>{{i18n "game_compendium.upload_one_asset"}}</h4>
                <p class="game-compendium-upload-hint">{{i18n "game_compendium.upload_hint"}}</p>
                <div class="game-compendium-upload-row">
                  <input name="slug" type="text" placeholder={{i18n "game_compendium.slug_placeholder"}} required disabled={{this.uploading}} />
                  <select name="asset_group" disabled={{this.uploading}}>
                    {{#each this.uploadAssetGroupOptions as |asset_group|}}<option value={{asset_group.slug}}>{{asset_group.name}}</option>{{/each}}
                  </select>
                  <input name="file" type="file" accept="image/png" required disabled={{this.uploading}} />
                </div>
                <textarea name="description" placeholder={{i18n "game_compendium.description_placeholder"}} disabled={{this.uploading}}></textarea>
                <DButton @label="game_compendium.upload_button" @isLoading={{this.uploading}} @disabled={{this.uploading}} @type="submit" class="btn-primary" />
              </form>

              <form class="game-compendium-upload">
                <h4>{{i18n "game_compendium.batch_upload"}}</h4>
                <p class="game-compendium-upload-hint">{{i18n "game_compendium.batch_upload_hint"}}</p>
                <select name="batch_asset_group" disabled={{this.uploading}}>
                  {{#each this.uploadAssetGroupOptions as |asset_group|}}<option value={{asset_group.slug}}>{{asset_group.name}}</option>{{/each}}
                </select>
                <input type="file" accept="image/png" multiple disabled={{this.uploading}} {{on "change" this.uploadBatch}} />
              </form>
            </section>
          {{/if}}

          {{#if (eq this.activeTab "asset_groups")}}
            <section class="game-compendium-section game-compendium-upload-panel">
              <h3>{{i18n "game_compendium.tabs.asset_groups"}}</h3>
              <form class="game-compendium-upload" {{on "submit" this.createAssetGroup}}>
                <h4>{{i18n "game_compendium.add_asset_group"}}</h4>
                <div class="game-compendium-upload-row">
                  <input type="text" placeholder={{i18n "game_compendium.asset_group_slug_placeholder"}} value={{this.newAssetGroupSlug}} {{on "input" this.updateNewAssetGroupSlug}} disabled={{this.creatingAssetGroup}} />
                  <input type="text" placeholder={{i18n "game_compendium.asset_group_name_placeholder"}} value={{this.newAssetGroupName}} {{on "input" this.updateNewAssetGroupName}} disabled={{this.creatingAssetGroup}} />
                  <DButton @label="game_compendium.add_asset_group" @isLoading={{this.creatingAssetGroup}} @disabled={{this.creatingAssetGroup}} @type="submit" class="btn-primary" />
                </div>
              </form>
              <div class="game-compendium-asset-group-list">
                {{#each this.asset_groups as |asset_group|}}
                  <div class="game-compendium-asset-group-row">
                    <span><strong>{{asset_group.name}}</strong> <code>{{asset_group.slug}}</code></span>
                    <DButton @action={{fn this.deleteAssetGroup asset_group}} @label="game_compendium.delete_unassign" @isLoading={{eq this.deletingAssetGroupSlug asset_group.slug}} @disabled={{this.deletingAssetGroupSlug}} class="btn-danger" />
                  </div>
                {{/each}}
              </div>
            </section>
          {{/if}}

          {{#if this.selected}}
            <button class="game-compendium-modal-backdrop" type="button" {{on "click" this.closeAsset}}></button>
            <section class="game-compendium-modal" aria-modal="true" role="dialog">
              <button class="btn-flat game-compendium-modal__close" type="button" {{on "click" this.closeAsset}}>×</button>
              <div class="game-compendium-modal__preview">
                <img src={{this.previewUrl}} alt={{this.selected.slug}} />
                {{#if this.replacementFile}}
                  <span class="game-compendium-modal__preview-label">{{i18n "game_compendium.replacement_preview"}}</span>
                {{/if}}
              </div>
              <form class="game-compendium-modal__form" {{on "submit" this.saveAsset}}>
                <h3>{{i18n "game_compendium.edit_asset"}}</h3>
                <label><span>{{i18n "game_compendium.slug_label"}}</span><input type="text" value={{this.editSlug}} {{on "input" this.updateEditSlug}} disabled={{this.saving}} /></label>
                <label><span>{{i18n "game_compendium.asset_group"}}</span><select value={{this.editAssetGroup}} {{on "change" this.updateEditAssetGroup}} disabled={{this.saving}}>{{#each this.uploadAssetGroupOptions as |asset_group|}}<option value={{asset_group.slug}} selected={{eq this.editAssetGroup asset_group.slug}}>{{asset_group.name}}</option>{{/each}}</select></label>
                <label><span>{{i18n "game_compendium.description_label"}}</span><textarea value={{this.editDescription}} {{on "input" this.updateEditDescription}} disabled={{this.saving}}></textarea></label>
                <label>
                  <span>{{i18n "game_compendium.replace_image"}}</span>
                  <input class="game-compendium-replacement-input" type="file" accept="image/png" {{on "change" this.setReplacementFile}} disabled={{this.saving}} />
                  <small>{{i18n "game_compendium.replace_image_hint"}}</small>
                </label>
                {{#if this.replacementFile}}
                  <div class="game-compendium-modal__replacement-selected">
                    <span>{{i18n "game_compendium.replacement_selected" filename=this.replacementFile.name}}</span>
                  <button class="btn btn-small" type="button" {{on "click" this.clearReplacementFile}} disabled={{this.saving}}>{{i18n "game_compendium.clear_replacement"}}</button>
                  </div>
                {{/if}}
                <div class="game-compendium-modal__actions">
                  <DButton @label="game_compendium.save" @isLoading={{this.saving}} @disabled={{this.saving}} @type="submit" class="btn-primary" />
                  <DButton @label="game_compendium.delete" @action={{this.deleteAsset}} @isLoading={{this.deleting}} @disabled={{this.deleting}} class="btn-danger" />
                  <DButton @label="game_compendium.cancel" @action={{this.closeAsset}} @disabled={{this.saving}} />
                </div>
              </form>
            </section>
          {{/if}}

          {{#if this.message}}<p class="game-compendium-status">{{this.message}}</p>{{/if}}
        {{/if}}
      </div>
    </div>
  </template>
}
