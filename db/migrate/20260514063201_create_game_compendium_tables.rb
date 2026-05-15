# frozen_string_literal: true

class CreateGameCompendiumTables < ActiveRecord::Migration[8.0]
  def change
    create_table :game_compendium_asset_groups do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.timestamps
    end

    add_index :game_compendium_asset_groups, :slug, unique: true

    create_table :game_compendium_assets do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.text :description, null: false, default: ""
      t.bigint :asset_group_id
      t.bigint :upload_id, null: false
      t.timestamps
    end

    add_index :game_compendium_assets, :slug, unique: true
    add_index :game_compendium_assets, :asset_group_id
    add_index :game_compendium_assets, :upload_id
  end
end
