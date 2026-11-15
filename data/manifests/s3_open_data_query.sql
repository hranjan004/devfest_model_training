-- UCSC Wildlife Vision v2 — Reproducible iNaturalist Open Data TSV Scan (CC0 / CC-BY only)
-- Prerequisite: extract s3://inaturalist-open-data/metadata/inaturalist-open-data-latest.tar.gz into /content/meta/

-- Query 1: 20 Target Species Candidates (California default bounding box)
COPY (
    SELECT
        o.observation_uuid AS observation_id,
        o.observer_id,
        obs.login AS observer_login,
        COALESCE(NULLIF(obs.name, ''), obs.login) AS photographer_credit,
        p.photo_id,
        p.photo_uuid,
        p.extension,
        p.width,
        p.height,
        LOWER(p.license) AS photo_license,
        t.name AS scientific_name,
        t.taxon_id,
        o.observed_on AS date_observed,
        o.positional_accuracy,
        o.latitude,
        o.longitude,
        FALSE AS is_ood,
        '' AS ood_group,
        CONCAT('https://inaturalist-open-data.s3.amazonaws.com/photos/', p.photo_id, '/large.', p.extension) AS large_image_url
    FROM read_csv('/content/meta/observations.csv.gz', delim='\t', header=true) AS o
    JOIN read_csv('/content/meta/photos.csv.gz', delim='\t', header=true) AS p
      ON o.observation_uuid = p.observation_uuid
    JOIN read_csv('/content/meta/taxa.csv.gz', delim='\t', header=true) AS t
      ON o.taxon_id = t.taxon_id
    LEFT JOIN read_csv('/content/meta/observers.csv.gz', delim='\t', header=true) AS obs
      ON o.observer_id = obs.observer_id
    WHERE o.quality_grade = 'research'
      AND LOWER(p.license) IN ('cc0', 'cc-by')
      AND t.taxon_id IN (42220, 42051, 41976, 42076, 41663, 41880, 180007, 46017, 46023, 43112, 906, 1409, 8234, 506118, 8010, 18209, 6317, 12727, 10094, 9420)
      AND p.width >= 256
      AND p.height >= 256
      AND o.latitude BETWEEN 32.5 AND 42.0
      AND o.longitude BETWEEN -124.5 AND -114.1
) TO 'data/manifests/inat_candidates.parquet' (FORMAT PARQUET);

-- Query 2: Resolved Hard-Negative OOD Taxa Candidates (configs/ood_taxa.yaml)
COPY (
    SELECT
        o.observation_uuid AS observation_id,
        o.observer_id,
        obs.login AS observer_login,
        COALESCE(NULLIF(obs.name, ''), obs.login) AS photographer_credit,
        p.photo_id,
        p.photo_uuid,
        p.extension,
        p.width,
        p.height,
        LOWER(p.license) AS photo_license,
        t.name AS scientific_name,
        t.taxon_id,
        o.observed_on AS date_observed,
        o.positional_accuracy,
        o.latitude,
        o.longitude,
        TRUE AS is_ood,
        CONCAT('https://inaturalist-open-data.s3.amazonaws.com/photos/', p.photo_id, '/large.', p.extension) AS large_image_url
    FROM read_csv('/content/meta/observations.csv.gz', delim='\t', header=true) AS o
    JOIN read_csv('/content/meta/photos.csv.gz', delim='\t', header=true) AS p
      ON o.observation_uuid = p.observation_uuid
    JOIN read_csv('/content/meta/taxa.csv.gz', delim='\t', header=true) AS t
      ON o.taxon_id = t.taxon_id
    LEFT JOIN read_csv('/content/meta/observers.csv.gz', delim='\t', header=true) AS obs
      ON o.observer_id = obs.observer_id
    WHERE o.quality_grade = 'research'
      AND LOWER(p.license) IN ('cc0', 'cc-by')
      AND t.taxon_id IN (46020, 46259, 43115, 43130, 42069, 47144, 118552, 42007, 42652, 8021, 506117, 8229, 6359, 73044, 792987, 18236, 12890, 145088, 9100)
      AND p.width >= 256
      AND p.height >= 256
      AND o.latitude BETWEEN 32.5 AND 42.0
      AND o.longitude BETWEEN -124.5 AND -114.1
) TO 'data/manifests/inat_ood_candidates.parquet' (FORMAT PARQUET);
