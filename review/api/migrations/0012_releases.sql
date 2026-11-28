-- Data releases (step 6, "Your contributions"): the signed manifests the site has loaded, and which release
-- carried each exported suggestion. A release is the SHA-256 of the signed manifest.json bytes, labelled
-- YYYY.MM.DD from the UTC day the site first loaded a newer file from it (YYYY.MM.DD-2, -3 for a second on one
-- day). A finished load of a dataset whose version is newer than the one before records the release and claims
-- that dataset's exported, unclaimed, non-note suggestions: main's manifest stays unsigned between a merged
-- review-pull PR and the owner's next make data-release, so the first newer load after "Mark exported" is the
-- release that carried it.
-- before_json is the target's JSON when the suggestion was accepted or declined (none for older decisions).
-- The owner applies this by hand (npm run migrate in review/api) before the Worker that reads it is deployed.

CREATE TABLE data_releases (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  manifest_sha256 TEXT UNIQUE, -- NULL only for the "Earlier releases" backfill row
  label TEXT NOT NULL UNIQUE,
  first_loaded_at TEXT
);

ALTER TABLE suggestions ADD COLUMN released_in INTEGER REFERENCES data_releases (id);
ALTER TABLE suggestions ADD COLUMN before_json TEXT;
CREATE INDEX suggestions_by_release ON suggestions (released_in);

-- Suggestions exported before this shipped: those exported before their dataset's last load went out in a
-- release the site never recorded, so they are filed under "Earlier releases". The rest wait for the next one.
INSERT INTO data_releases (manifest_sha256, label, first_loaded_at)
SELECT NULL, 'Earlier releases', NULL
WHERE EXISTS (
  SELECT 1 FROM suggestions s JOIN snapshot_files f ON f.name = s.dataset
  WHERE s.action <> 'note' AND s.exported_at IS NOT NULL AND s.exported_at < f.imported_at);

UPDATE suggestions SET released_in = (SELECT id FROM data_releases WHERE label = 'Earlier releases')
WHERE action <> 'note' AND exported_at IS NOT NULL
  AND exported_at < (SELECT imported_at FROM snapshot_files WHERE name = suggestions.dataset);
