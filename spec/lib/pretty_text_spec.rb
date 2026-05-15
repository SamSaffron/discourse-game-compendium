# frozen_string_literal: true

RSpec.describe PrettyText do
  def cooked(markdown)
    PrettyText.cook(markdown)
  end

  it "renders an asset reference alone on a line as a block" do
    html = cooked("[[Corruption]]")

    expect(html).to include('class="game-compendium-card-block"')
    expect(html).to include('data-game-compendium-slug="corruption"')
    expect(html).to include("/game-compendium/assets/corruption/image.png")
    expect(html).not_to include(
      'class="game-compendium-ref game-compendium-card-ref"'
    )
  end

  it "renders an upgraded asset reference alone on a line as an upgraded block" do
    html = cooked("[[Corruption+]]")

    expect(html).to include('class="game-compendium-card-block"')
    expect(html).to include('data-game-compendium-slug="corruption"')
    expect(html).to include('data-game-compendium-upgraded="true"')
    expect(html).to include("/game-compendium/assets/corruption/image.png")
  end

  it "ignores surrounding whitespace when deciding whether to render a block" do
    html = cooked("  [[Corruption]]  ")

    expect(html).to include('class="game-compendium-card-block"')
    expect(html).to include("/game-compendium/assets/corruption/image.png")
    expect(html).not_to include(
      'class="game-compendium-ref game-compendium-card-ref"'
    )
  end

  it "renders asset refs inside prose as inline refs only" do
    html = cooked("hello [[Corruption]] world")

    expect(html).to include(
      'class="game-compendium-ref game-compendium-card-ref"'
    )
    expect(html).to include('data-game-compendium-slug="corruption"')
    expect(html).to include("/game-compendium/assets/corruption/image.png")
    expect(html).not_to include('class="game-compendium-card-block"')
  end

  it "renders known terms as term refs, not asset blocks" do
    html = cooked("[[Sharp]]")

    expect(html).to include(
      'class="game-compendium-ref game-compendium-term-ref game-compendium-term-enchantment"'
    )
    expect(html).to include('data-game-compendium-slug="sharp"')
    expect(html).to include("Increases damage on this card by X.")
    expect(html).not_to include('class="game-compendium-card-block"')
  end

  it "does not promote the old game-compendium-card syntax" do
    html = cooked("[game-compendium-card:Corruption]")

    expect(html).to include("[game-compendium-card:Corruption]")
    expect(html).not_to include('class="game-compendium-card-block"')
    expect(html).not_to include("/game-compendium/assets/corruption/image.png")
  end
end
