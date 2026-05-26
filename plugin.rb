# frozen_string_literal: true

# name: discourse-game-compendium
# about: Game Compendium — game asset markdown embeds, composer autocomplete, and delegated asset management
# version: 0.2.0
# authors: Game Compendium

enabled_site_setting :game_compendium_enabled

register_svg_icon "rectangle-list"

register_asset "stylesheets/common/game-compendium.scss"

add_api_key_scope(
  :game_compendium,
  {
    manage: {
      actions: %w[
        game_compendium_assets#index
        game_compendium_assets#upload_asset
        game_compendium_assets#update_asset
        game_compendium_assets#delete_asset
        game_compendium_assets#bulk_update_assets
        game_compendium_assets#bulk_delete_assets
        game_compendium_assets#asset_groups
        game_compendium_assets#create_asset_group
        game_compendium_assets#delete_asset_group
      ],
      formats: :json
    }
  }
)

after_initialize do
  require_relative "app/models/game_compendium/asset_group"
  require_relative "app/models/game_compendium/asset"

  module ::GameCompendium
    PLUGIN_NAME = "discourse-game-compendium"

    def self.can_manage_assets?(user)
      return false unless SiteSetting.game_compendium_enabled
      return false unless user
      return true if user.staff?

      group_ids =
        SiteSetting
          .game_compendium_asset_manager_groups
          .to_s
          .split("|")
          .map(&:to_i)
          .reject(&:zero?)
      return false if group_ids.empty?

      GroupUser.exists?(group_id: group_ids, user_id: user.id)
    end
  end

  add_to_serializer(:current_user, :can_manage_game_compendium_assets) do
    GameCompendium.can_manage_assets?(object)
  end

  # rubocop:disable Discourse/Plugins/NoMonkeyPatching
  class ::GameCompendiumAssetsController < ::ApplicationController
    requires_login

    def index
      ensure_allowed!

      render json: asset_payload
    end

    def asset_groups
      ensure_allowed!

      render json: { asset_groups: asset_groups_json }
    end

    def create_asset_group
      ensure_allowed!

      slug = sanitize_slug(params[:slug].presence || params[:name])
      if slug.blank?
        return render_json_error("Invalid asset_group slug", status: 422)
      end

      name = params[:name].to_s.strip.presence || slug.titleize
      asset_group = GameCompendium::AssetGroup.new(slug: slug, name: name)

      if asset_group.save
        render json: { asset_group: asset_group_json(asset_group) }
      else
        render_json_error(asset_group.errors.full_messages.first, status: 422)
      end
    end

    def delete_asset_group
      ensure_allowed!

      slug = clean_existing_slug(params[:slug])
      if slug.blank?
        return render_json_error("Invalid asset_group slug", status: 422)
      end

      asset_group = GameCompendium::AssetGroup.find_by(slug: slug)
      if asset_group.blank?
        return render_json_error("AssetGroup not found", status: 422)
      end

      GameCompendium::Asset.where(asset_group_id: asset_group.id).update_all(
        asset_group_id: nil
      )
      asset_group.destroy!

      render json: { deleted: slug }
    end

    def update_asset
      ensure_allowed!

      result = update_asset_record(params[:current_slug])
      return render_json_error(result[:error], status: 422) if result[:error]

      render json: asset_json(result[:asset])
    rescue Discourse::InvalidAccess
      raise
    rescue StandardError => e
      render_json_error("Update failed: #{e.message}", status: 500)
    end

    def delete_asset
      ensure_allowed!

      result = delete_asset_record(params[:current_slug])
      return render_json_error(result[:error], status: 422) if result[:error]

      render json: { deleted: result[:slug] }
    rescue Discourse::InvalidAccess
      raise
    rescue StandardError => e
      render_json_error("Delete failed: #{e.message}", status: 500)
    end

    def bulk_update_assets
      ensure_allowed!

      result = bulk_update_asset_records
      return render_json_error(result[:error], status: 422) if result[:error]

      render json: { updated: result[:count] }
    rescue Discourse::InvalidAccess
      raise
    rescue StandardError => e
      render_json_error("Bulk update failed: #{e.message}", status: 500)
    end

    def bulk_delete_assets
      ensure_allowed!

      result = bulk_delete_asset_records
      return render_json_error(result[:error], status: 422) if result[:error]

      render json: { deleted: result[:count] }
    rescue Discourse::InvalidAccess
      raise
    rescue StandardError => e
      render_json_error("Bulk delete failed: #{e.message}", status: 500)
    end

    def upload_asset
      params[:files].present? ? upload_many : upload_one
    end

    private

    def asset_payload
      assets = filtered_assets
      total = assets.count
      offset = [params[:offset].to_i, 0].max
      requested_limit = params[:limit].to_i
      requested_limit = 60 if requested_limit <= 0
      requested_limit = [requested_limit, 200].min
      page = assets.offset(offset).limit(requested_limit).to_a

      {
        total: total,
        assets: page.map { |asset| asset_json(asset) },
        offset: offset,
        limit: requested_limit,
        has_more: offset + page.size < total,
        asset_groups: asset_groups_json
      }
    end

    def filtered_assets(
      asset_group_filter: params[:asset_group],
      query_filter: params[:q]
    )
      assets =
        GameCompendium::Asset.includes(:asset_group, :upload).order(:slug)

      if asset_group_filter.present?
        asset_group = asset_group_filter.to_s
        assets =
          if asset_group == "__ungrouped"
            assets.where(asset_group_id: nil)
          else
            assets.joins(:asset_group).where(
              game_compendium_asset_groups: {
                slug: asset_group
              }
            )
          end
      end

      if query_filter.present?
        query =
          "%#{ActiveRecord::Base.sanitize_sql_like(query_filter.to_s.downcase)}%"
        assets =
          assets.where(
            "LOWER(game_compendium_assets.slug) LIKE ? OR LOWER(game_compendium_assets.description) LIKE ?",
            query,
            query
          )
      end

      assets
    end

    def asset_json(asset)
      {
        slug: asset.slug,
        autocomplete_target: asset.slug,
        name: asset.name,
        asset_group: asset.asset_group&.slug,
        description: asset.description.to_s,
        url: upload_url(asset.upload)
      }
    end

    def upload_one
      ensure_allowed!

      result = write_asset_record(params[:slug].to_s.strip, params[:file])
      return render_json_error(result[:error], status: 422) if result[:error]

      render json: asset_json(result[:asset])
    rescue Discourse::InvalidAccess
      raise
    rescue StandardError => e
      render_json_error("Upload failed: #{e.message}", status: 500)
    end

    def upload_many
      ensure_allowed!

      files = Array(params[:files]).select { |file| file.respond_to?(:read) }
      return render_json_error("No files uploaded", status: 422) if files.empty?

      uploaded = []
      errors = []

      description_by_slug = batch_descriptions_by_slug(files)
      png_files = files.select { |file| png_filename?(original_filename(file)) }
      if png_files.empty?
        return render_json_error("No PNG files uploaded", status: 422)
      end

      png_files.each do |file|
        original_name = original_filename(file)
        raw_slug = File.basename(original_name, File.extname(original_name))
        slug = sanitize_slug(raw_slug)
        result =
          write_asset_record(
            raw_slug,
            file,
            description:
              description_by_slug.fetch(slug, params[:description].to_s.strip)
          )
        if result[:error]
          errors << "#{original_name}: #{result[:error]}"
        else
          uploaded << result[:asset].slug
        end
      end

      render json: { uploaded: uploaded, errors: errors }
    end

    def write_asset_record(
      raw_slug,
      file,
      description: params[:description].to_s.strip
    )
      slug = sanitize_slug(raw_slug)
      if slug.blank?
        return { error: "Invalid slug: path characters are not allowed" }
      end
      return { error: "No file uploaded" } unless file.respond_to?(:read)

      validation_error = validate_png(file)
      return { error: validation_error } if validation_error

      asset_group = find_optional_asset_group(params[:asset_group])
      if params[:asset_group].present? && asset_group.blank?
        return { error: "Invalid asset_group" }
      end
      if GameCompendium::Asset.exists?(slug: slug)
        return { error: "An asset already exists with slug #{slug}" }
      end

      upload = create_upload(file, slug)
      return { error: upload_error(upload) } unless upload&.persisted?

      asset =
        GameCompendium::Asset.create(
          slug: slug,
          name: params[:name].presence || slug.titleize,
          asset_group: asset_group,
          description: description,
          upload: upload
        )

      if asset.errors.present?
        return { error: asset.errors.full_messages.first }
      end

      { asset: asset }
    end

    def update_asset_record(current_slug)
      old_slug = clean_existing_slug(current_slug)
      return { error: "Invalid current slug" } if old_slug.blank?

      asset = GameCompendium::Asset.find_by(slug: old_slug)
      return { error: "Asset not found" } if asset.blank?

      new_slug = sanitize_slug(params[:slug].presence || old_slug)
      if new_slug.blank?
        return { error: "Invalid slug: path characters are not allowed" }
      end

      if new_slug != old_slug && GameCompendium::Asset.exists?(slug: new_slug)
        return { error: "An asset already exists with slug #{new_slug}" }
      end

      file = params[:file]
      if file.present?
        validation_error = validate_png(file)
        return { error: validation_error } if validation_error
      end

      asset_group = find_optional_asset_group(params[:asset_group])
      if params[:asset_group].present? && asset_group.blank?
        return { error: "Invalid asset_group" }
      end

      upload = create_upload(file, new_slug) if file.present?
      if file.present? && !upload&.persisted?
        return { error: upload_error(upload) }
      end

      asset.slug = new_slug
      asset.name = params[:name].to_s.strip if params.key?(:name)
      asset.name = new_slug.titleize if asset.name.blank?
      asset.asset_group = asset_group if params.key?(:asset_group)
      asset.description = params[:description].to_s.strip if params.key?(
        :description
      )
      asset.upload = upload if upload.present?

      return { error: asset.errors.full_messages.first } unless asset.save

      { asset: asset }
    end

    def delete_asset_record(current_slug)
      slug = clean_existing_slug(current_slug)
      return { error: "Invalid slug" } if slug.blank?

      asset = GameCompendium::Asset.find_by(slug: slug)
      return { error: "Asset not found" } if asset.blank?

      asset.destroy!

      { slug: slug }
    end

    def bulk_update_asset_records
      scope = bulk_asset_scope
      return scope if scope.is_a?(Hash) && scope[:error]
      return { error: "Missing asset_group" } unless params.key?(:asset_group)

      asset_group = find_optional_asset_group(params[:asset_group])
      if params[:asset_group].present? && asset_group.blank?
        return { error: "Invalid asset_group" }
      end

      ids = scope.pluck(:id)
      return { count: 0 } if ids.empty?

      GameCompendium::Asset.where(id: ids).update_all(
        asset_group_id: asset_group&.id,
        updated_at: Time.zone.now
      )

      { count: ids.size }
    end

    def bulk_delete_asset_records
      scope = bulk_asset_scope
      return scope if scope.is_a?(Hash) && scope[:error]

      count = 0
      scope.find_each do |asset|
        asset.destroy!
        count += 1
      end

      { count: count }
    end

    def bulk_asset_scope
      if truthy_param?(params[:all_matching])
        return(
          filtered_assets(
            asset_group_filter: params[:filter_asset_group],
            query_filter: params[:q]
          ).reorder(nil)
        )
      end

      slugs = bulk_slugs
      return { error: "Select at least one asset" } if slugs.empty?

      GameCompendium::Asset.where(slug: slugs)
    end

    def bulk_slugs
      Array(params[:slugs])
        .flat_map { |value| value.to_s.split(",") }
        .filter_map { |slug| clean_existing_slug(slug) }
        .uniq
    end

    def truthy_param?(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end

    def original_filename(file)
      return file.original_filename.to_s if file.respond_to?(:original_filename)

      ""
    end

    def png_filename?(filename)
      File.extname(filename).casecmp(".png").zero?
    end

    def txt_filename?(filename)
      File.extname(filename).casecmp(".txt").zero?
    end

    def batch_descriptions_by_slug(files)
      files.each_with_object({}) do |file, descriptions|
        filename = original_filename(file)
        next unless txt_filename?(filename)

        slug = sanitize_slug(File.basename(filename, File.extname(filename)))
        next if slug.blank?

        file.rewind if file.respond_to?(:rewind)
        descriptions[slug] = file.read.to_s.strip
        file.rewind if file.respond_to?(:rewind)
      end
    end

    def create_upload(file, slug)
      file.rewind if file.respond_to?(:rewind)
      UploadCreator.new(
        file,
        "#{slug}.png",
        for_site_setting: true,
        skip_image_processing: true
      ).create_for(current_user.id)
    end

    def upload_url(upload)
      Discourse.store.cdn_url(upload.url)
    end

    def upload_error(upload)
      return "Upload failed" if upload.blank?

      upload.errors.full_messages.presence&.join(", ") || "Upload failed"
    end

    def find_optional_asset_group(raw_asset_group)
      asset_group = raw_asset_group.to_s.strip
      return nil if asset_group.blank?

      slug = clean_existing_slug(asset_group)
      return nil if slug.blank?

      GameCompendium::AssetGroup.find_by(slug: slug)
    end

    def asset_groups_json
      GameCompendium::AssetGroup
        .order(Arel.sql("LOWER(name) ASC"))
        .map { |asset_group| asset_group_json(asset_group) }
    end

    def asset_group_json(asset_group)
      { slug: asset_group.slug, name: asset_group.name }
    end

    def sanitize_slug(raw_slug)
      raw_slug = raw_slug.to_s.strip
      return nil if raw_slug.blank?
      if raw_slug.include?("/") || raw_slug.include?("\\") ||
           raw_slug.include?("..")
        return nil
      end

      slug =
        raw_slug
          .downcase
          .gsub(/[^a-z0-9]+/, "_")
          .delete_prefix("_")
          .delete_suffix("_")
      return nil if slug.empty? || slug.length > 100

      slug
    end

    def clean_existing_slug(raw_slug)
      raw_slug = raw_slug.to_s.strip
      return nil if raw_slug.blank?
      return nil unless raw_slug.match?(/\A[a-z0-9_]+\z/)

      raw_slug
    end

    def validate_png(file)
      return "No file uploaded" unless file.respond_to?(:read)

      header = file.read(8)
      file.rewind
      return "File must be a valid PNG" unless header.b == "\x89PNG\r\n\x1a\n".b

      nil
    end

    def ensure_allowed!
      raise Discourse::InvalidAccess unless allowed?
    end

    def allowed?
      GameCompendium.can_manage_assets?(current_user)
    end
  end

  class ::GameCompendiumAssetImagesController < ::ApplicationController
    skip_before_action :check_xhr,
                       :redirect_to_login_if_required,
                       :redirect_to_profile_if_required

    def show
      raise Discourse::NotFound unless SiteSetting.game_compendium_enabled

      slug = params[:slug].to_s
      raise Discourse::NotFound unless slug.match?(/\A[a-z0-9_]+\z/)

      asset = GameCompendium::Asset.includes(:upload).find_by(slug: slug)
      raise Discourse::NotFound if asset&.upload.blank?

      redirect_to Discourse.store.cdn_url(asset.upload.url),
                  status: :found,
                  allow_other_host: true
    end
  end

  class ::GameCompendiumAssetDataController < ::ApplicationController
    def index
      raise Discourse::NotFound unless SiteSetting.game_compendium_enabled

      assets =
        GameCompendium::Asset
          .includes(:asset_group, :upload)
          .order(:slug)
          .map do |asset|
            {
              slug: asset.slug,
              name: asset.name,
              image: Discourse.store.cdn_url(asset.upload.url),
              description: asset.description.to_s,
              asset_group: asset.asset_group&.slug
            }
          end

      render json: { assets: assets }
    end
  end
  # rubocop:enable Discourse/Plugins/NoMonkeyPatching

  Discourse::Application.routes.append do
    get "/game-compendium" => "home_page#blank"
    get "/game-compendium/asset-data" => "game_compendium_asset_data#index",
        :format => :json
    get "/game-compendium/assets/:slug/image.png" =>
          "game_compendium_asset_images#show"
    get "/game-compendium/assets" => "game_compendium_assets#index",
        :format => :json
    post "/game-compendium/assets" => "game_compendium_assets#upload_asset",
         :format => :json
    delete "/game-compendium/assets/bulk" =>
             "game_compendium_assets#bulk_delete_assets",
           :format => :json
    patch "/game-compendium/assets/bulk" =>
            "game_compendium_assets#bulk_update_assets",
          :format => :json
    patch "/game-compendium/assets/:current_slug" =>
            "game_compendium_assets#update_asset",
          :format => :json
    delete "/game-compendium/assets/:current_slug" =>
             "game_compendium_assets#delete_asset",
           :format => :json

    get "/game-compendium/asset-groups" =>
          "game_compendium_assets#asset_groups",
        :format => :json
    post "/game-compendium/asset-groups" =>
           "game_compendium_assets#create_asset_group",
         :format => :json
    delete "/game-compendium/asset-groups/:slug" =>
             "game_compendium_assets#delete_asset_group",
           :format => :json
  end
end
