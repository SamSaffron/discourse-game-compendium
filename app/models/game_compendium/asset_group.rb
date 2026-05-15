# frozen_string_literal: true

module GameCompendium
  class AssetGroup < ActiveRecord::Base
    self.table_name = "game_compendium_asset_groups"

    has_many :assets, class_name: "GameCompendium::Asset", dependent: :nullify

    validates :slug, presence: true, uniqueness: true
    validates :name, presence: true
  end
end
