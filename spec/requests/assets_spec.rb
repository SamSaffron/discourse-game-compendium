# frozen_string_literal: true

RSpec.describe "Game Compendium asset management", type: :request do
  fab!(:upload)
  fab!(:primary_asset_group) do
    GameCompendium::AssetGroup.create!(slug: "attacks", name: "Attacks")
  end
  fab!(:secondary_asset_group) do
    GameCompendium::AssetGroup.create!(slug: "powers", name: "Powers")
  end
  fab!(:existing_asset) do
    GameCompendium::Asset.create!(
      slug: "existing",
      name: "Existing",
      asset_group: primary_asset_group,
      description: "starter asset",
      upload: upload
    )
  end

  before { SiteSetting.game_compendium_enabled = true }

  def png_bytes
    Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg=="
    )
  end

  def upload_file(name: "asset.png", bytes: png_bytes)
    tmp =
      Tempfile.new(
        [File.basename(name, ".*"), File.extname(name)],
        binmode: true
      )
    tmp.write(bytes)
    tmp.rewind
    Rack::Test::UploadedFile.new(
      tmp.path,
      name.end_with?(".txt") ? "text/plain" : "image/png",
      true,
      original_filename: name
    )
  end

  def api_headers(api_key, user)
    { "Api-Key" => api_key.key, "Api-Username" => user.username }
  end

  it "denies anonymous users" do
    get "/game-compendium/assets.json"
    expect(response.status).to eq(403)
  end

  it "denies normal users outside configured manager groups" do
    sign_in(Fabricate(:user))

    get "/game-compendium/assets.json"
    expect(response.status).to eq(403)
  end

  it "allows management through the game_compendium API key scope" do
    admin = Fabricate(:admin)
    api_key =
      Fabricate(
        :api_key,
        user: admin,
        scope_mode: :granular,
        api_key_scopes: [
          Fabricate.build(
            :api_key_scope,
            resource: "game_compendium",
            action: "manage"
          )
        ]
      )

    get "/game-compendium/assets.json", headers: api_headers(api_key, admin)
    expect(response.status).to eq(200)

    post "/game-compendium/asset-groups.json",
         params: {
           slug: "jokers",
           name: "Jokers"
         },
         headers: api_headers(api_key, admin)
    expect(response.status).to eq(200)
  end

  it "rejects API keys without the game_compendium management scope" do
    admin = Fabricate(:admin)
    api_key =
      Fabricate(
        :api_key,
        user: admin,
        scope_mode: :granular,
        api_key_scopes: [
          Fabricate.build(:api_key_scope, resource: "topics", action: "read")
        ]
      )

    get "/game-compendium/assets.json", headers: api_headers(api_key, admin)

    expect(response.status).to eq(403)
  end

  it "serializes whether the current user can manage compendium assets" do
    user = Fabricate(:user)
    group = Fabricate(:group)
    SiteSetting.game_compendium_asset_manager_groups = group.id.to_s

    expect(GameCompendium.can_manage_assets?(user)).to eq(false)

    group.add(user)
    expect(GameCompendium.can_manage_assets?(user)).to eq(true)
    expect(GameCompendium.can_manage_assets?(Fabricate(:admin))).to eq(true)
  end

  it "allows a configured group member to see assets" do
    group = Fabricate(:group)
    user = Fabricate(:user)
    group.add(user)
    SiteSetting.game_compendium_asset_manager_groups = group.id.to_s
    sign_in(user)

    get "/game-compendium/assets.json"
    expect(response.status).to eq(200)
  end

  it "lists unified assets with asset_group metadata from the database" do
    sign_in(Fabricate(:admin))

    get "/game-compendium/assets.json"

    expect(response.status).to eq(200)
    json = response.parsed_body
    expect(json["total"]).to eq(1)
    expect(json["assets"].first).to include(
      "slug" => "existing",
      "autocomplete_target" => "existing",
      "name" => "Existing",
      "asset_group" => "attacks",
      "description" => "starter asset",
      "url" => upload.url
    )
    expect(
      json["asset_groups"].map { |asset_group| asset_group["slug"] }
    ).to include("attacks", "powers")
  end

  it "paginates and filters by text and asset_group" do
    sign_in(Fabricate(:admin))
    GameCompendium::Asset.create!(
      slug: "alpha",
      name: "Alpha",
      asset_group: primary_asset_group,
      description: "first",
      upload: Fabricate(:upload)
    )
    GameCompendium::Asset.create!(
      slug: "alphabet",
      name: "Alphabet",
      asset_group: secondary_asset_group,
      description: "letters",
      upload: Fabricate(:upload)
    )
    GameCompendium::Asset.create!(
      slug: "beta",
      name: "Beta",
      asset_group: primary_asset_group,
      upload: Fabricate(:upload)
    )

    get "/game-compendium/assets.json",
        params: {
          q: "alpha",
          asset_group: "attacks",
          offset: 0,
          limit: 1
        }

    expect(response.status).to eq(200)
    json = response.parsed_body
    expect(json["total"]).to eq(1)
    expect(json["assets"].map { |asset| asset["slug"] }).to eq(["alpha"])
    expect(json["has_more"]).to eq(false)
  end

  it "filters ungrouped assets" do
    sign_in(Fabricate(:admin))
    GameCompendium::Asset.create!(
      slug: "loose",
      name: "Loose",
      upload: Fabricate(:upload)
    )

    get "/game-compendium/assets.json", params: { asset_group: "__ungrouped" }

    expect(response.status).to eq(200)
    expect(response.parsed_body["assets"].map { |asset| asset["slug"] }).to eq(
      ["loose"]
    )
  end

  it "returns autocomplete card data from database uploads" do
    get "/game-compendium/asset-data.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body["assets"].first).to include(
      "slug" => "existing",
      "name" => "Existing",
      "image" => upload.url,
      "description" => "starter asset",
      "asset_group" => "attacks"
    )
  end

  it "accepts an individual png with metadata" do
    sign_in(Fabricate(:admin))

    expect {
      post "/game-compendium/assets.json",
           params: {
             slug: "Test Asset",
             asset_group: "attacks",
             description: "Deal damage",
             file: upload_file
           }
    }.to change(GameCompendium::Asset, :count).by(1).and change(
            Upload,
            :count
          ).by(1)

    expect(response.status).to eq(200)
    expect(response.parsed_body).to include(
      "slug" => "test_asset",
      "asset_group" => "attacks",
      "description" => "Deal damage"
    )
    asset = GameCompendium::Asset.find_by!(slug: "test_asset")
    expect(asset.upload).to be_present
    expect(asset.upload.extension).to eq("png")
    expect(asset.upload.original_filename).to eq("test_asset.png")
    expect(
      File.binread(Rails.public_path.join(asset.upload.url.delete_prefix("/")))
    ).to eq(png_bytes)
    expect(UploadReference.exists?(target: asset, upload: asset.upload)).to eq(
      true
    )
  end

  it "batch uploads using filenames, one asset_group, and matching txt descriptions" do
    sign_in(Fabricate(:admin))

    post "/game-compendium/assets.json",
         params: {
           asset_group: "powers",
           files: [
             upload_file(name: "Tiny Crown.png"),
             upload_file(name: "Tiny Crown.txt", bytes: "A very small crown")
           ]
         }

    expect(response.status).to eq(200)
    expect(response.parsed_body["uploaded"]).to include("tiny_crown")
    asset = GameCompendium::Asset.find_by!(slug: "tiny_crown")
    expect(asset.asset_group).to eq(secondary_asset_group)
    expect(asset.description).to eq("A very small crown")
  end

  it "rejects unsafe slugs" do
    sign_in(Fabricate(:admin))

    post "/game-compendium/assets.json",
         params: {
           slug: "../bad",
           file: upload_file
         }
    expect(response.status).to eq(422)
  end

  it "rejects non-png content" do
    sign_in(Fabricate(:admin))

    post "/game-compendium/assets.json",
         params: {
           slug: "fake",
           file: upload_file(bytes: "nope")
         }
    expect(response.status).to eq(422)
  end

  it "updates slug, asset_group, description, and image" do
    sign_in(Fabricate(:admin))
    old_upload = existing_asset.upload

    patch "/game-compendium/assets/existing.json",
          params: {
            slug: "Renamed",
            asset_group: "powers",
            description: "new text",
            file: upload_file(name: "new.png")
          }

    expect(response.status).to eq(200)
    expect(response.parsed_body).to include(
      "slug" => "renamed",
      "asset_group" => "powers",
      "description" => "new text"
    )
    asset = GameCompendium::Asset.find_by!(slug: "renamed")
    expect(asset.upload).not_to eq(old_upload)
    expect(UploadReference.exists?(target: asset, upload: asset.upload)).to eq(
      true
    )
    expect(UploadReference.exists?(target: asset, upload: old_upload)).to eq(
      false
    )
  end

  it "rejects renaming over an existing asset" do
    sign_in(Fabricate(:admin))
    GameCompendium::Asset.create!(
      slug: "taken",
      name: "Taken",
      upload: Fabricate(:upload)
    )

    patch "/game-compendium/assets/existing.json", params: { slug: "taken" }

    expect(response.status).to eq(422)
    expect(GameCompendium::Asset.exists?(slug: "existing")).to eq(true)
  end

  it "deletes an existing asset and its upload reference" do
    sign_in(Fabricate(:admin))
    asset_id = existing_asset.id

    delete "/game-compendium/assets/existing.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body["deleted"]).to eq("existing")
    expect(GameCompendium::Asset.exists?(slug: "existing")).to eq(false)
    expect(
      UploadReference.exists?(
        target_type: "GameCompendium::Asset",
        target_id: asset_id,
        upload: upload
      )
    ).to eq(false)
  end

  it "bulk updates selected assets" do
    sign_in(Fabricate(:admin))
    other_asset =
      GameCompendium::Asset.create!(
        slug: "other",
        name: "Other",
        asset_group: primary_asset_group,
        upload: Fabricate(:upload)
      )

    patch "/game-compendium/assets/bulk.json",
          params: {
            slugs: %w[existing other],
            asset_group: "powers"
          }

    expect(response.status).to eq(200)
    expect(response.parsed_body["updated"]).to eq(2)
    expect(existing_asset.reload.asset_group).to eq(secondary_asset_group)
    expect(other_asset.reload.asset_group).to eq(secondary_asset_group)
  end

  it "bulk updates all assets matching the current filters to a target asset group" do
    sign_in(Fabricate(:admin))
    alpha =
      GameCompendium::Asset.create!(
        slug: "alpha",
        name: "Alpha",
        asset_group: primary_asset_group,
        upload: Fabricate(:upload)
      )
    beta =
      GameCompendium::Asset.create!(
        slug: "beta",
        name: "Beta",
        asset_group: secondary_asset_group,
        upload: Fabricate(:upload)
      )

    patch "/game-compendium/assets/bulk.json",
          params: {
            all_matching: true,
            filter_asset_group: "attacks",
            asset_group: "powers"
          }

    expect(response.status).to eq(200)
    expect(response.parsed_body["updated"]).to eq(2)
    expect(existing_asset.reload.asset_group).to eq(secondary_asset_group)
    expect(alpha.reload.asset_group).to eq(secondary_asset_group)
    expect(beta.reload.asset_group).to eq(secondary_asset_group)
  end

  it "bulk deletes all assets matching the current filters" do
    sign_in(Fabricate(:admin))
    GameCompendium::Asset.create!(
      slug: "alpha",
      name: "Alpha",
      asset_group: primary_asset_group,
      upload: Fabricate(:upload)
    )
    GameCompendium::Asset.create!(
      slug: "beta",
      name: "Beta",
      asset_group: secondary_asset_group,
      upload: Fabricate(:upload)
    )

    delete "/game-compendium/assets/bulk.json",
           params: {
             all_matching: true,
             filter_asset_group: "attacks"
           }

    expect(response.status).to eq(200)
    expect(response.parsed_body["deleted"]).to eq(2)
    expect(GameCompendium::Asset.exists?(slug: "existing")).to eq(false)
    expect(GameCompendium::Asset.exists?(slug: "alpha")).to eq(false)
    expect(GameCompendium::Asset.exists?(slug: "beta")).to eq(true)
  end

  it "rejects bulk operations without a selection" do
    sign_in(Fabricate(:admin))

    delete "/game-compendium/assets/bulk.json", params: { slugs: [] }

    expect(response.status).to eq(422)
  end

  it "redirects stable image URLs to the stored upload" do
    existing_asset

    get "/game-compendium/assets/existing/image.png"

    expect(response.status).to eq(302)
    expect(response.location).to end_with(upload.url)
  end

  it "creates and deletes asset_groups without deleting assets" do
    sign_in(Fabricate(:admin))

    post "/game-compendium/asset-groups.json",
         params: {
           slug: "jokers",
           name: "Jokers"
         }
    expect(response.status).to eq(200)
    expect(response.parsed_body["asset_group"]).to include(
      "slug" => "jokers",
      "name" => "Jokers"
    )

    patch "/game-compendium/assets/existing.json",
          params: {
            asset_group: "jokers"
          }
    expect(response.status).to eq(200)
    expect(response.parsed_body["asset_group"]).to eq("jokers")

    delete "/game-compendium/asset-groups/jokers.json"
    expect(response.status).to eq(200)
    expect(GameCompendium::Asset.exists?(slug: "existing")).to eq(true)

    get "/game-compendium/assets.json"
    expect(
      response.parsed_body["assets"].find do |asset|
        asset["slug"] == "existing"
      end[
        "asset_group"
      ]
    ).to be_nil
  end
end
