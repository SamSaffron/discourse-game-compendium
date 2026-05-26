# frozen_string_literal: true

module GameCompendium
  class Asset < ActiveRecord::Base
    self.table_name = "game_compendium_assets"

    belongs_to :asset_group,
               class_name: "GameCompendium::AssetGroup",
               optional: true
    belongs_to :upload
    has_many :upload_references, as: :target, dependent: :destroy

    after_save :ensure_upload_reference, if: :saved_change_to_upload_id?

    validates :slug, presence: true, uniqueness: true
    validates :name, presence: true
    validates :description, presence: true, allow_blank: true
    validates :upload, presence: true

    private

    def ensure_upload_reference
      UploadReference.ensure_exist!(upload_ids: [upload_id], target: self)
    end
  end
end

# == Schema Information
#
# Table name: game_compendium_assets
#
#  id             :bigint           not null, primary key
#  description    :text             default(""), not null
#  name           :string           not null
#  slug           :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  asset_group_id :bigint
#  upload_id      :bigint           not null
#
# Indexes
#
#  index_game_compendium_assets_on_asset_group_id  (asset_group_id)
#  index_game_compendium_assets_on_slug            (slug) UNIQUE
#  index_game_compendium_assets_on_upload_id       (upload_id)
#
