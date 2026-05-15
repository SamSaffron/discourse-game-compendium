# Game Compendium persistence improvement plan

## Goals

- Store all game compendium content in Discourse-managed database tables.
- Store images as Discourse uploads and keep them referenced so orphan cleanup does not delete them.
- Do not use plugin `public/` storage for compendium content.
- Do not add legacy, migration, import, fallback, or compatibility paths. This is a brand new plugin.
- Add request/model specs that cover authorization, upload retention, CRUD, and markdown rendering.

## Target data model

Create plugin tables:

1. `game_compendium_asset_groups`
   - `id`
   - `slug`, unique, normalized with the existing slug rules
   - `name`
   - timestamps

2. `game_compendium_assets`
   - `id`
   - `slug`, unique, normalized with the existing slug rules
   - `asset_group_id`, nullable foreign key to `game_compendium_asset_groups`
   - `upload_id`, non-null foreign key to `uploads`
   - `description`, nullable text
   - timestamps

Model associations:

- `GameCompendium::AssetGroup has_many :assets`
- `GameCompendium::Asset belongs_to :asset_group, optional: true`
- `GameCompendium::Asset belongs_to :upload`
- `GameCompendium::Asset has_many :upload_references, as: :target`

Whenever an asset upload changes, call `UploadReference.ensure_exist!(upload_ids: [asset.upload_id], target: asset)` so Discourse upload cleanup sees the image as referenced. Deleting an asset should delete its `UploadReference`; the upload can then follow normal cleanup rules unless another reference exists.

## Implementation phases

### Phase 1: Schema and models

- Add plugin migrations for the two tables and indexes.
- Add models under the plugin namespace.
- Add validations for slug format/length, asset_group uniqueness, upload presence, and PNG image constraints.
- Do not seed game-specific asset_group concepts in code; asset_groups are manager-created database rows.

### Phase 2: Upload-backed storage

- Replace direct file writes with `UploadCreator` using the current manager user or the system user.
- Store the returned upload on `game_compendium_assets.upload_id`.
- Create/refresh `UploadReference` for each asset record after upload assignment.
- Return `upload.url`/`upload.short_url`-based URLs from the API.
- Keep markdown/autocomplete data using the asset slug as the stable public identifier.

### Phase 3: Remove public-folder storage code

- Delete runtime reads from `asset-asset_groups.json`, `asset-metadata.json`, and plugin public image directories.
- Delete runtime writes to plugin public image directories.
- Delete public-folder mirroring behavior entirely.
- Do not replace these with fallback code.
- After this phase, database rows plus Discourse uploads are the only source of truth.

### Phase 4: Controller/API rewrite

- Rewrite listing/filtering/pagination to query `GameCompendium::Asset.includes(:asset_group, :upload)`.
- Rewrite asset_group CRUD to use `GameCompendium::AssetGroup` records.
- Rewrite upload/update/delete flows to operate transactionally on DB rows and upload references.
- Keep existing routes and response shapes where useful for the current UI.
- Consider returning `head :no_content` for delete endpoints only if the UI no longer requires response bodies.

### Phase 5: Frontend cleanup

- Update the admin component to consume upload-backed asset URLs.
- Move user-facing strings in the component into translations as part of the cleanup.
- Remove assumptions that asset images live under plugin public paths.

## Test plan

### Model specs

- AssetGroup slug uniqueness and normalization rules.
- Asset requires a slug and upload.
- Asset keeps exactly one `UploadReference` to its current upload.
- Updating the upload removes the previous reference and creates the new one.
- Deleting an asset removes its upload reference.

### Request specs

- Existing authorization coverage: anonymous denied, normal user denied, manager group allowed, scoped API key allowed.
- List endpoint returns asset_groups, upload-backed URLs, asset_group filters, search, pagination, and ungrouped assets.
- Single upload creates an upload, asset row, asset_group association, and upload reference.
- Batch upload handles partial failures without rolling back successful files.
- Update endpoint supports slug/asset_group/description/image changes transactionally.
- Delete endpoint removes the asset row and upload reference.
- AssetGroup delete leaves assets intact and sets them ungrouped.

### Storage specs

- Runtime code does not read asset_group or metadata JSON files.
- Runtime code does not read or write plugin public image files.
- Upload/update paths create Discourse uploads, not files under the plugin directory.
- Every created or updated asset has an `UploadReference` so its upload is not orphaned.

### Markdown/pretty-text specs

- Existing card/reference rendering continues to resolve a slug.
- Rendered image URLs come from the DB/upload-backed asset when present.
- Missing slugs fail safely without broken privileged file access.

## Explicit non-goals

- No legacy compatibility.
- No public-folder fallback.
- No import/migration path from JSON or public PNG files.
- No mirroring uploads back into plugin public directories.
