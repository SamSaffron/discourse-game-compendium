# frozen_string_literal: true

module PageObjects
  module Pages
    class GameCompendium < Base
      def visit_page(tab: nil)
        path = "/game-compendium"
        path += "?tab=#{tab}" if tab
        visit(path)
        self
      end

      def open_asset_groups
        click_link(I18n.t("js.game_compendium.tabs.asset_groups"))
        self
      end

      def open_upload
        click_link(I18n.t("js.game_compendium.tabs.upload"))
        self
      end

      def open_browse
        click_link(I18n.t("js.game_compendium.tabs.browse"))
        self
      end

      def add_asset_group(slug:, name:)
        within(".game-compendium-upload-panel") do
          fill_in(
            placeholder:
              I18n.t("js.game_compendium.asset_group_slug_placeholder"),
            with: slug
          )
          fill_in(
            placeholder:
              I18n.t("js.game_compendium.asset_group_name_placeholder"),
            with: name
          )
          click_button(I18n.t("js.game_compendium.add_asset_group"))
        end
        self
      end

      def upload_asset(slug:, description:, file_path:, asset_group: nil)
        within(
          ".game-compendium-upload",
          text: I18n.t("js.game_compendium.upload_one_asset")
        ) do
          fill_in(
            placeholder: I18n.t("js.game_compendium.slug_placeholder"),
            with: slug
          )
          select(asset_group, from: "asset_group") if asset_group
          fill_in(
            placeholder: I18n.t("js.game_compendium.description_placeholder"),
            with: description
          )
          attach_file("file", file_path)
          click_button(I18n.t("js.game_compendium.upload_button"))
        end
        self
      end

      def filter_assets(query)
        fill_in(
          placeholder: I18n.t("js.game_compendium.search_placeholder"),
          with: query
        )
        self
      end

      def has_asset_group?(name, slug)
        has_css?(".game-compendium-asset-group-row", text: name) &&
          has_css?(".game-compendium-asset-group-row code", text: slug)
      end

      def has_asset?(slug)
        has_css?(".game-compendium-card-item", text: slug)
      end

      def has_toast?(text)
        has_css?(".fk-d-toast", text: text)
      end

      def has_status?(text)
        has_css?(".game-compendium-status", text: text)
      end
    end
  end
end
