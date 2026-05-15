# frozen_string_literal: true

require_relative "page_objects/pages/game_compendium"

RSpec.describe "Game compendium" do
  fab!(:admin)
  fab!(:upload)

  let(:compendium_page) { PageObjects::Pages::GameCompendium.new }

  before do
    SiteSetting.game_compendium_enabled = true
    sign_in(admin)
  end

  def png_file
    file = Tempfile.new(%w[game-compendium .png], binmode: true)
    file.write(
      Base64.decode64(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg=="
      )
    )
    file.rewind
    file
  end

  it "creates asset_groups from the UI and shows duplicate validation errors" do
    compendium_page.visit_page(tab: "asset_groups")
    compendium_page.add_asset_group(slug: "cards", name: "Cards")

    expect(compendium_page).to have_toast(
      I18n.t("js.game_compendium.messages.added_asset_group", name: "Cards")
    )
    expect(compendium_page).to have_asset_group("Cards", "cards")

    compendium_page.add_asset_group(slug: "cards", name: "Cards")

    expect(page).to have_css(
      ".dialog-body",
      text: "Slug has already been taken"
    )
  end

  it "uploads and browses assets using database asset_groups" do
    GameCompendium::AssetGroup.create!(slug: "attacks", name: "Attacks")
    image = png_file

    compendium_page.visit_page(tab: "upload")
    compendium_page.upload_asset(
      slug: "Bash",
      description: "Deal damage",
      asset_group: "Attacks",
      file_path: image.path
    )

    expect(compendium_page).to have_toast(
      I18n.t("js.game_compendium.messages.uploaded_asset", slug: "bash")
    )

    compendium_page.open_browse.filter_assets("bash")

    expect(compendium_page).to have_asset("bash")
  ensure
    image&.close!
  end
end
