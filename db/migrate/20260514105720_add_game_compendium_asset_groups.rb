# frozen_string_literal: true

class AddGameCompendiumAssetGroups < ActiveRecord::Migration[8.0]
  def up
    unless table_exists?(:game_compendium_asset_groups)
      create_table :game_compendium_asset_groups do |t|
        t.string :slug, null: false
        t.string :name, null: false
        t.timestamps
      end
    end

    add_index :game_compendium_asset_groups,
              :slug,
              unique: true,
              if_not_exists: true

    if table_exists?(:game_compendium_assets) &&
         !column_exists?(:game_compendium_assets, :asset_group_id)
      add_column :game_compendium_assets, :asset_group_id, :bigint
    end

    if table_exists?(:game_compendium_assets)
      add_index :game_compendium_assets, :asset_group_id, if_not_exists: true
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
