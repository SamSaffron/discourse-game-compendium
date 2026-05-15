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
