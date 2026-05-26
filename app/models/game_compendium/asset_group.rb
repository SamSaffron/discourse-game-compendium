# frozen_string_literal: true

module GameCompendium
  class AssetGroup < ActiveRecord::Base
    self.table_name = "game_compendium_asset_groups"

    has_many :assets, class_name: "GameCompendium::Asset", dependent: :nullify

    validates :slug, presence: true, uniqueness: true
    validates :name, presence: true
  end
end

# == Schema Information
#
# Table name: game_compendium_asset_groups
#
#  id         :bigint           not null, primary key
#  name       :string           not null
#  slug       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_game_compendium_asset_groups_on_slug  (slug) UNIQUE
#
