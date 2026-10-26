-- =====================================================================
-- PROJET SQL : ANALYSE DES VENTES D'UNE BOUTIQUE EN LIGNE (Online Retail, UCI)
-- Base PostgreSQL : online_retail
-- Fichier source : "Online Retail.csv" (séparateur ; et décimale ,)
-- Ordre : -- Ordre : 0 (mise en place) -> 1 (audit) -> 2 (nettoyage) -> 3 (analyses pays et produits, contrôles qualité) 
-- -> 4 (définition du CA, évolution mensuelle) -> 5 (meilleurs clients) -> 6 (annulations)
-- =====================================================================


-- =====================================================================
-- 0. MISE EN PLACE
-- =====================================================================

-- 0.1 Création de la table brute, tout en TEXT pour que l'import du CSV ne déforme rien
CREATE TABLE online_retail_raw (
    invoice_no   TEXT,
    stock_code   TEXT,
    description  TEXT,
    quantity     TEXT,
    invoice_date TEXT,
    unit_price   TEXT,
    customer_id  TEXT,
    country      TEXT
);

-- IMPORT DU CSV (manuel, dans pgAdmin)

-- 0.2 Conversion des types 
ALTER TABLE online_retail_raw
    ALTER COLUMN unit_price TYPE NUMERIC(12, 4)
        USING REPLACE(unit_price, ',', '.')::NUMERIC(12, 4),
    ALTER COLUMN quantity TYPE INTEGER
        USING quantity::INTEGER;


-- 0.3 Contrôle de l'import
SELECT
    COUNT(*)                                    AS nb_lignes,
    COUNT(*) FILTER (WHERE unit_price = 0)      AS prix_zero,
    ROUND(SUM(quantity * unit_price), 3)        AS total_quantite_x_prix
FROM online_retail_raw;

-- =====================================================================
-- 1. EXPLORATION ET AUDIT DE LA TABLE BRUTE
-- =====================================================================

-- 1.1 Aperçu des 10 premières lignes de la table brute
SELECT *
FROM online_retail_raw
LIMIT 10;

-- 1.2 Période couverte, après conversion du texte en vraie date. Attendu : du 2010-12-01 au 2011-12-09
SELECT
    MIN(TO_TIMESTAMP(TRIM(invoice_date), 'DD/MM/YYYY HH24:MI')::timestamp) AS premiere_date,
    MAX(TO_TIMESTAMP(TRIM(invoice_date), 'DD/MM/YYYY HH24:MI')::timestamp) AS derniere_date
FROM online_retail_raw
WHERE invoice_date IS NOT NULL;

-- 1.3a Nombre de groupes de lignes strictement identiques
SELECT COUNT(*) AS groupes_meme_facture_code_quantite
FROM (
    SELECT 1
    FROM online_retail_raw
    GROUP BY invoice_no,
        stock_code,
        description,
        quantity,
        invoice_date,
        unit_price,
        customer_id,
        country
    HAVING COUNT(*) > 1
) AS groupes_doublons;

-- 1.3 Créer une vue regroupant les doublons exacts et leur nombre d'occurrences
CREATE OR REPLACE VIEW groupes_doublons AS
SELECT
    invoice_no, stock_code, description, quantity, invoice_date,
    unit_price, customer_id, country,
    COUNT(*) AS nombre_occurrences
FROM online_retail_raw
GROUP BY invoice_no, stock_code, description, quantity, invoice_date,
         unit_price, customer_id, country
HAVING COUNT(*) > 1;

-- 1.3c Afficher les 20 groupes de doublons les plus fréquents
SELECT *
FROM groupes_doublons
ORDER BY nombre_occurrences DESC
LIMIT 20;

-- 1.3d : liste des lignes excédentaires (doublons) de online_retail_raw,
SELECT
    COUNT(*)                          AS nb_groupes_doublons,
    SUM(nombre_occurrences)           AS total_lignes_concernees,
    SUM(nombre_occurrences - 1)       AS lignes_excedentaires
FROM groupes_doublons;

-- lignes_excedentaires : 5268

-- 1.4a Valeurs manquantes (NULL ou chaînes vides) dans chaque colonne
SELECT
    COUNT(*) FILTER (WHERE invoice_no IS NULL OR TRIM(invoice_no) = '')       AS invoice_no_missing,
    COUNT(*) FILTER (WHERE stock_code IS NULL OR TRIM(stock_code) = '')       AS stock_code_missing,
    COUNT(*) FILTER (WHERE description IS NULL OR TRIM(description) = '')     AS description_missing,
    COUNT(*) FILTER (WHERE quantity IS NULL)                                  AS quantity_missing,
    COUNT(*) FILTER (WHERE invoice_date IS NULL OR TRIM(invoice_date) = '')   AS invoice_date_missing,
    COUNT(*) FILTER (WHERE unit_price IS NULL)                                AS unit_price_missing,
    COUNT(*) FILTER (WHERE customer_id IS NULL OR TRIM(customer_id) = '')     AS customer_id_missing,
    COUNT(*) FILTER (WHERE country IS NULL OR TRIM(country) = '')             AS country_missing
FROM online_retail_raw;

-- ==> description manquante = 1454, customer_id manquant = 135080, les autres = 0

-- 1.4b Factures associées à plusieurs clients distincts 
SELECT
    invoice_no,
    COUNT(DISTINCT NULLIF(TRIM(customer_id), ''))            AS nb_clients,
    STRING_AGG(DISTINCT NULLIF(TRIM(customer_id), ''), ', ') AS customer_ids
FROM online_retail_raw
GROUP BY invoice_no
HAVING COUNT(DISTINCT NULLIF(TRIM(customer_id), '')) > 1
ORDER BY nb_clients DESC;


-- 1.4c Nombre de factures mixtes (client connu sur certaines lignes, absent sur d'autres) 
SELECT COUNT(*) AS factures_mixtes
FROM (
    SELECT invoice_no
    FROM online_retail_raw
    GROUP BY invoice_no
    HAVING COUNT(*) FILTER (WHERE NULLIF(TRIM(customer_id), '') IS NOT NULL) > 0
       AND COUNT(*) FILTER (WHERE NULLIF(TRIM(customer_id), '') IS NULL) > 0
) AS t;


-- 1.4d Qualité de la colonne customer_id : lignes avec et sans client
SELECT
    COUNT(*) AS total_lignes,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(customer_id), '') IS NOT NULL) AS lignes_avec_client,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(customer_id), '') IS NULL)     AS lignes_sans_client
FROM online_retail_raw;


-- 1.5 Identifiants clients restés au format décimal à cause de l'export (ex. 17850.0)
SELECT COUNT(*) AS ids_avec_point
FROM online_retail_raw
WHERE customer_id LIKE '%.%';


-- 1.6 Casse des codes produits : si les deux nombres diffèrent, un même code est écrit en majuscules et en minuscules 
SELECT
    COUNT(DISTINCT stock_code)        AS codes,
    COUNT(DISTINCT UPPER(stock_code)) AS codes_normalises
FROM online_retail_raw;

-- 1.7 Codes qui ne commencent pas par 5 chiffres (frais, ajustements, bons cadeaux...) à examiner à l'oeil.
SELECT stock_code, description, COUNT(*) AS nb_lignes
FROM online_retail_raw
WHERE stock_code !~ '^[0-9]{5}'
GROUP BY stock_code, description
ORDER BY nb_lignes DESC;


-- 1.8 Impact des 1454 descriptions manquantes
SELECT
	COUNT(*)                                                      AS nb_lignes,
    COUNT(*) FILTER (WHERE unit_price = 0)                        AS prix_zero,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(customer_id), '') IS NULL) AS sans_client,
    COUNT(*) FILTER (WHERE quantity < 0)                          AS qte_negative,
    COUNT(DISTINCT stock_code)                                    AS codes_distincts
FROM online_retail_raw
WHERE description IS NULL OR TRIM(description) = '';

-- ==> 1454 lignes, toutes à prix 0 et sans client, 862 à quantité négative, 960 codes distincts (ce ne sont pas des ventes)

-- 1.9 Panorama des anomalies
SELECT
    COUNT(*) FILTER (WHERE quantity < 0)                               AS qte_negative,
    COUNT(*) FILTER (WHERE quantity = 0)                               AS qte_zero,
    COUNT(*) FILTER (WHERE unit_price < 0)                             AS prix_negatif,
    COUNT(*) FILTER (WHERE unit_price = 0)                             AS prix_zero,
    COUNT(*) FILTER (WHERE invoice_no LIKE 'C%')                       AS lignes_annulation,
    COUNT(*) FILTER (WHERE quantity < 0
                       AND invoice_no NOT LIKE 'C%')                   AS qte_neg_hors_annulation,
    COUNT(*) FILTER (WHERE unit_price = 0
                       AND NULLIF(TRIM(customer_id), '') IS NOT NULL)  AS prix_zero_avec_client
FROM online_retail_raw;

-- ==> qte_negative 10624, qte_zero 0, prix_negatif 2, prix_zero 2515, annulations 9288, qte_neg_hors_annulation 1336, prix_zero_avec_client 40

-- 1.10 Classement de chaque ligne dans UNE catégorie (la première condition vraie gagne), avec une ligne 8_TOTAL qui doit valoir 541909 lignes et 9747747.93.
WITH classement AS (
    SELECT
        quantity,
        unit_price,
        CASE
            WHEN invoice_no LIKE 'C%'                                     THEN '1_annulation'
            WHEN unit_price < 0                                           THEN '2_prix_negatif'
            WHEN unit_price = 0 AND NULLIF(TRIM(customer_id), '') IS NULL THEN '3_prix_zero_sans_client'
            WHEN unit_price = 0                                           THEN '4_prix_zero_avec_client'
            WHEN quantity < 0                                             THEN '5_qte_negative_hors_annulation'
            WHEN stock_code !~ '^[0-9]{5}'                                THEN '6_code_special'
            ELSE '7_vente'
        END AS categorie
    FROM online_retail_raw
)
SELECT categorie, COUNT(*) AS nb_lignes, ROUND(SUM(quantity * unit_price), 2) AS montant
FROM classement
GROUP BY categorie

UNION ALL

SELECT '8_TOTAL', COUNT(*), ROUND(SUM(quantity * unit_price), 2)
FROM classement

ORDER BY categorie;


-- 1.11 Les 42 lignes à examiner à l'oeil 
SELECT *
FROM online_retail_raw
WHERE unit_price < 0
   OR (unit_price = 0 AND NULLIF(TRIM(customer_id), '') IS NOT NULL)
ORDER BY unit_price, stock_code;

-- ==> les 2 prix négatifs (Adjust bad debt) et les 40 prix à 0 avec client.

-- 1.12 Codes spéciaux hors annulations et hors prix à 0 : nombre de lignes et montant par code (POST, DOT, M, BANK CHARGES, gift_...).
SELECT stock_code, description, COUNT(*) AS nb_lignes, ROUND(SUM(quantity * unit_price), 2) AS montant
FROM online_retail_raw
WHERE invoice_no NOT LIKE 'C%'
  AND unit_price > 0
  AND stock_code !~ '^[0-9]{5}'
GROUP BY stock_code, description
ORDER BY nb_lignes DESC;


-- =====================================================================
-- 2. CONSTRUCTION DE LA TABLE NETTOYÉE 
-- =====================================================================

-- 2.1 Création de online_retail_clean : date convertie en TIMESTAMP, codes en majuscules, vides mis à NULL, colonne montant, colonne type_ligne
-- (vente, annulation, frais_livraison...) et colonne is_doublon (TRUE pour les copies d'une ligne identique). Aucune ligne n'est supprimée.
DROP TABLE IF EXISTS online_retail_clean;

CREATE TABLE online_retail_clean AS
WITH base AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY invoice_no, stock_code, description, quantity,
                         invoice_date, unit_price, customer_id, country
            ORDER BY invoice_no
        ) AS rn
    FROM online_retail_raw
)
SELECT
    invoice_no,
    UPPER(TRIM(stock_code))                                           AS stock_code,
    NULLIF(TRIM(description), '')                                     AS description,
    quantity,
    TO_TIMESTAMP(TRIM(invoice_date), 'DD/MM/YYYY HH24:MI')::timestamp AS invoice_date,
    unit_price,
    NULLIF(TRIM(customer_id), '')                                     AS customer_id,
    country,
    ROUND(quantity * unit_price, 4)                                   AS montant,
    CASE
        WHEN invoice_no LIKE 'C%'                                         THEN 'annulation'
        WHEN UPPER(TRIM(stock_code)) IN ('M', 'B')                        THEN 'ajustement_manuel'
        WHEN UPPER(TRIM(stock_code)) IN ('POST', 'DOT', 'C2')             THEN 'frais_livraison'
        WHEN UPPER(TRIM(stock_code)) IN ('BANK CHARGES', 'AMAZONFEE')     THEN 'frais_externes'
        WHEN LEFT(UPPER(TRIM(stock_code)), 9) = 'GIFT_0001'               THEN 'bon_cadeau'
        WHEN UPPER(TRIM(stock_code)) IN ('S', 'PADS')                     THEN 'autre_non_produit'
        WHEN unit_price = 0 AND NULLIF(TRIM(customer_id), '') IS NULL     THEN 'ajustement_stock'
        WHEN unit_price = 0                                               THEN 'prix_zero_avec_client'
        ELSE 'vente'
    END                                                               AS type_ligne,
    (rn > 1)                                                          AS is_doublon
FROM base;

-- 2.2 Contrôle de online_retail_clean par type_ligne
SELECT
    COALESCE(type_ligne, 'TOTAL')  AS type_ligne,
    COUNT(*)                       AS nb_lignes,
    ROUND(SUM(montant), 2)         AS montant
FROM online_retail_clean
GROUP BY ROLLUP (type_ligne)
ORDER BY GROUPING(type_ligne), type_ligne;

/*TOTAL 541909 et 9747747.93 ; vente 527758 ; annulation 9288 ; frais_livraison 1981 ;
ajustement_stock 2464 ; ajustement_manuel 331 ; bon_cadeau 34 ; prix_zero_avec_client 33 ; frais_externes 14 ; autre_non_produit 6 */

-- 2.3 Les doublons

-- 2.3a Nombre de lignes marquées comme doublons
SELECT COUNT(*) FILTER (WHERE is_doublon) AS nb_doublons
FROM online_retail_clean;

-- 5268 doublons (les lignes excédentaires de l'audit 1.3d).

--2.3b Impact des doublons sur le chiffre d'affaires des ventes :

SELECT
	SUM(unit_price*quantity) FILTER (WHERE is_doublon) 	AS CA_exclue,
    SUM(unit_price*quantity) FILTER (WHERE NOT is_doublon) 	AS CA_concerve,
	ROUND (100 * (SUM(unit_price*quantity) FILTER (WHERE is_doublon )) / SUM(quantity*unit_price),2) AS pct_ca_doublons
FROM online_retail_clean
WHERE type_ligne = 'vente';

SELECT COUNT(*)
FROM online_retail_clean
WHERE type_ligne = 'vente' AND is_doublon;

/* Les lignes strictement identiques sur les 8 colonnes (5221 lignes) ont été considérées comme des doublons et exclues de l’analyse. 
Elles représentent 0,24 % du chiffre d’affaires des ventes (≈ 24 200 sur 10,27 M), un impact négligeable sur les conclusions. 
Les lignes sont marquées (is_doublon) et non supprimées, ce qui permet de les réintégrer si besoin.*/

-- 2.3c Factures contenant des doublons : nombre total de lignes et nombre de lignes en doublon,
SELECT
    invoice_no,
    COUNT(*)                                AS nb_lignes,
    COUNT(*) FILTER (WHERE is_doublon)      AS nb_doublons
FROM online_retail_clean
WHERE type_ligne = 'vente'
GROUP BY invoice_no
HAVING COUNT(*) FILTER (WHERE is_doublon) > 0
ORDER BY nb_doublons DESC
LIMIT 20;

/* Les doublons exacts se concentrent dans de grosses factures. Quelques-unes semblent avoir été intégralement enregistrées deux fois 
(environ 50 % de lignes en doublon), les autres présentent des répétitions partielles. Leur exclusion est retenue par prudence, 
avec un impact de 0,24 % sur le CA */

-- 2.3d Les doublons qui ne sont pas de type vente : on les affiche pour juger s'ils sont de vrais doublons ou des lignes légitimes (retours, annulations, ajustements)
SELECT *
FROM online_retail_clean
WHERE is_doublon
  AND type_ligne <> 'vente'
ORDER BY invoice_no, stock_code;


SELECT
type_ligne,
COUNT(*) AS nb_ligne,
COUNT(DISTINCT stock_code) AS nbre_code,
STRING_AGG (DISTINCT stock_code, ', ' 
	ORDER BY stock_code) AS code,
SUM(montant) AS Montant
FROM online_retail_clean
WHERE is_doublon AND type_ligne <> 'vente'
GROUP BY type_ligne;


SELECT 
SUM(montant) AS total
FROM online_retail_clean
WHERE is_doublon
  AND type_ligne <> 'vente'

/* Doublons hors ventes (47 lignes) : 5 ajustements de stock (montant 0), 5 copies de la ligne "Manual" de la facture 572344 (+360) 
et 37 lignes d'annulation (-2 832,76), soit -2 472,76 net(≈ -0,02 % du CA des ventes). Hors périmètre de v_ventes, donc sans effet sur 
l'analyse des ventes : lignes marquées is_doublon et conservées. À revérifier si analyse des retours (facture C570556 = ~95 % du montant des annulations). */
   
-- 2.4 Vue des ventes analysables : lignes de type 'vente' qui ne sont pas des copies. Toutes les analyses partent de cette vue.
CREATE OR REPLACE VIEW v_ventes AS
SELECT *
FROM online_retail_clean
WHERE type_ligne = 'vente'
  AND NOT is_doublon;

-- 2.5 Profil de la base d'analyse
SELECT
    COUNT(*)                                                      AS nb_lignes,
    COUNT(DISTINCT invoice_no)                                    AS nb_factures,
    COUNT(DISTINCT customer_id)                                   AS nb_clients,
    COUNT(DISTINCT stock_code)                                    AS nb_produits,
    COUNT(DISTINCT country)                                       AS nb_pays,
    MIN(invoice_date)::date                                       AS premiere_date,
    MAX(invoice_date)::date                                       AS derniere_date,
    ROUND(SUM(montant), 2)                                        AS ca_total,
    ROUND(100.0 * COUNT(*) FILTER (WHERE customer_id IS NULL)
          / COUNT(*), 1)                                          AS pct_lignes_sans_client
FROM v_ventes;

/*522537 lignes, 19773 factures, 4334 clients, 3798 produits, 38 pays, du 2010-12-01 au 2011-12-09, CA brut 10247219.32, 25.1 % de lignes sans client */

-- 2.6 Liste des colonnes de online_retail_clean avec leur type. Attendu : 11 colonnes, is_doublon en dernier, de type boolean.
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'online_retail_clean'
ORDER BY ordinal_position;


-- =====================================================================
-- 3. ANALYSES BUSINESS : PAYS ET PRODUITS (avec contrôles de qualité)
-- =====================================================================

-- 3.1 CA par pays avec la part de chaque pays dans le CA total et le CA moyen par facture.

SELECT
    country                                                              AS pays,
    ROUND(SUM(montant), 2)                                               AS ca,
    ROUND(100.0 * SUM(montant) / (SELECT SUM(montant) FROM v_ventes), 1) AS pct_ca,
    COUNT(DISTINCT invoice_no)                                           AS nb_factures,
    ROUND(SUM(montant) / COUNT(DISTINCT invoice_no), 0)                  AS ca_par_facture,
    COUNT(DISTINCT customer_id)                                          AS nb_clients
FROM v_ventes
GROUP BY country
ORDER BY ca DESC;


/*le Royaume-Uni représente 85.1 % du CA */

-- 3.2 Les 10 plus grosses lignes de vente par montant, avec la première annulation postérieure du même client, du même produit, de quantité opposée
-- ET de même prix unitaire (numéro et date affichés)
SELECT
    v.invoice_no,
    v.invoice_date,
    v.customer_id,
    v.stock_code,
    v.quantity,
    v.unit_price,
    ROUND(v.montant, 2)         AS montant,
    a.invoice_no                AS annulation_facture,
    a.invoice_date              AS annulation_date,
    (a.invoice_no IS NOT NULL)  AS annulation_possible
FROM v_ventes v
LEFT JOIN LATERAL (
    SELECT c.invoice_no, c.invoice_date
    FROM online_retail_clean c
    WHERE c.type_ligne = 'annulation'
      AND NOT c.is_doublon
      AND c.customer_id = v.customer_id
      AND c.stock_code  = v.stock_code
      AND c.quantity    = -v.quantity
      AND c.unit_price  = v.unit_price
      AND c.invoice_date >= v.invoice_date
    ORDER BY c.invoice_date
    LIMIT 1
) a ON TRUE
ORDER BY v.montant DESC
LIMIT 10;


-- 3.3 Codes produit ayant plusieurs descriptions distinctes (casse et espaces ignorés) dans les ventes
SELECT
    stock_code,
    COUNT(DISTINCT UPPER(TRIM(description)))  AS nb_descriptions,
    STRING_AGG(DISTINCT description, ' | ')   AS descriptions,
    COUNT(*) OVER ()                          AS total_codes_concernes
FROM v_ventes
WHERE description IS NOT NULL
GROUP BY stock_code
HAVING COUNT(DISTINCT UPPER(TRIM(description))) > 1
ORDER BY nb_descriptions DESC, stock_code;

/* Contrôle des libellés : 212 codes produit ont plusieurs descriptions dans v_ventes. La grande majorité
   sont le même produit écrit différemment (fautes, ponctuation, ordre des mots, abréviations) ;
   quelques codes (ex. 22963, 23041, 22952, 85123A) correspondent à des variantes (couleur, taille, quantité).
   Décision : l'analyse produit se fait par stock_code, avec la description la plus fréquente comme libellé ;
   l'effet du mélange de variantes sur les totaux est jugé négligeable. */


-- 3.4a Formats des codes produit dans les ventes et annulations (hors copies)
SELECT
    CASE
        WHEN stock_code ~ '^[0-9]{5}$'       THEN '1_cinq_chiffres_exactement'
        WHEN stock_code ~ '^[0-9]{5}[A-Z]+$' THEN '2_cinq_chiffres_plus_lettres'
        WHEN stock_code ~ '^[0-9]+$'         THEN '3_autres_codes_numeriques'
        ELSE                                      '4_autres_formats'
    END                         AS format_code,
    COUNT(DISTINCT stock_code)  AS nb_codes,
    COUNT(*)                    AS nb_lignes,
    ROUND(SUM(montant), 2)      AS ca_net,
    STRING_AGG(DISTINCT type_ligne, ' | ')   AS type_ligne,
    MIN(stock_code)             AS exemple
FROM online_retail_clean
WHERE NOT is_doublon
  AND type_ligne IN ('vente', 'annulation')
GROUP BY 1
ORDER BY 1;

-- 5 chiffres = 2879 codes ; 5 chiffres + lettres = 926 codes (874585.25 de CA net) ; autres formats = 16 codes


-- 3.4b Codes du format 4 dans les ventes et annulations hors copies
SELECT
    stock_code,
    type_ligne,
    COUNT(*)               AS nb_lignes,
    ROUND(SUM(montant), 2) AS montant
FROM online_retail_clean
WHERE NOT is_doublon
  AND type_ligne IN ('vente', 'annulation')
  AND stock_code !~ '^[0-9]{5}[A-Z]*$'
GROUP BY stock_code, type_ligne
ORDER BY ABS(SUM(montant)) DESC;

/* Contrôle des formats de code (3.5 et 3.5b): 3805 codes ont le format d'un vrai produit (5 chiffres,avec ou sans lettres : 2879 + 926);
16 codes d'autres formats (616 lignes) ne sont pas des produits. Le type de ligne (vente ou annulation) vient du numéro de facture, 
pas du code : un même produit peut donc avoir les deux. Décision : le top 10 produits (3.7) ne garde que les 3805 codes produit. */


-- 3.5a Codes produit dont le prix unitaire maximum dépasse 10 fois le prix médian (ventes hors copies, au moins 5 lignes) :
-- signal d'un code qui mélange plusieurs produits ou d'une erreur de prix.

SELECT
    stock_code,
    COUNT(*)                                                                    AS nb_lignes,
    MIN(unit_price)                                                             AS prix_min,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY unit_price)::numeric, 2)  AS prix_median,
    MAX(unit_price)                                                             AS prix_max,
    ROUND(SUM(montant), 2)                                                      AS ca,
    (SELECT ROUND(SUM(montant), 2) FROM v_ventes)                               AS ca_total,
    ROUND(100.0 * SUM(montant) / (SELECT SUM(montant) FROM v_ventes), 2)        AS pct_ca
FROM v_ventes
GROUP BY stock_code
HAVING COUNT(*) >= 5
   AND MAX(unit_price) > 10 * PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY unit_price)
ORDER BY ca DESC;

/* Contrôle des prix : 55 codes ont un prix maximum supérieur à 10 fois leur prix médian (au moins 5 lignes de vente).
   Ensemble, ils représentent au plus 1 % du CA des ventes (22502 : 0,50 %, dont une vente de 38 970 annulée ;
   chacun des autres : 0,08 % au plus). L'impact sur les totaux est jugé négligeable. */

-- 3.5b Index pour accélérer le rapprochement ventes/annulations : recherche directe par client et par montant
CREATE INDEX idx_retail_clean_client_montant
ON online_retail_clean (customer_id, montant);


-- 3.6 Top 10 des produits par CA net (ventes moins annulations, hors copies)
WITH descriptions_comptees AS (
    SELECT stock_code, description, COUNT(*) AS nb_occurrences
    FROM v_ventes
    WHERE description IS NOT NULL
    GROUP BY stock_code, description
),
descriptions_classees AS (
    SELECT
        stock_code,
        description,
        ROW_NUMBER() OVER (
            PARTITION BY stock_code
            ORDER BY nb_occurrences DESC, description ASC
        ) AS rang
    FROM descriptions_comptees
),
ca_produit AS (
    SELECT
        c.stock_code,
        SUM(c.montant) FILTER (WHERE c.type_ligne = 'vente')      AS ca_brut,
        SUM(c.montant) FILTER (WHERE c.type_ligne = 'annulation') AS retours,
        SUM(c.montant)                                            AS ca_net,
        SUM(c.quantity)                                           AS quantite_nette
    FROM online_retail_clean c
    WHERE NOT c.is_doublon
      AND c.type_ligne IN ('vente', 'annulation')
      AND c.stock_code ~ '^[0-9]{5}[A-Z]*$'
      AND NOT (c.type_ligne = 'vente' AND EXISTS (
            SELECT 1
            FROM online_retail_clean a
            WHERE a.type_ligne = 'annulation'
              AND NOT a.is_doublon
              AND a.customer_id = c.customer_id
              AND a.montant = -c.montant
              AND a.invoice_date >= c.invoice_date))
      AND NOT (c.type_ligne = 'annulation' AND EXISTS (
            SELECT 1
            FROM online_retail_clean s
            WHERE s.type_ligne = 'vente'
              AND NOT s.is_doublon
              AND s.customer_id = c.customer_id
              AND s.montant = -c.montant
              AND s.invoice_date <= c.invoice_date))
    GROUP BY c.stock_code
)
SELECT
    p.stock_code,
    d.description,
    ROUND(p.ca_brut, 2) AS ca_brut,
    ROUND(p.retours, 2) AS retours,
    ROUND(p.ca_net, 2)  AS ca_net,
	ROUND(100.0 * p.ca_net / NULLIF((SELECT SUM(montant) FROM v_ventes), 0), 1) AS pct_ca,
    p.quantite_nette
FROM ca_produit p
LEFT JOIN descriptions_classees d
       ON p.stock_code = d.stock_code
      AND d.rang = 1
ORDER BY p.ca_net DESC
LIMIT 10;

/* Top 10 des produits par CA net : codes produit uniquement (5 chiffres, avec ou sans lettres), après retrait des
   ventes annulées (rapprochées de leur annulation par client et montant opposé). Le rapprochement est
   approximatif ; seul ca_net est comparable, ca_brut et retours ne sont plus des totaux bruts. */

SELECT stock_code, min(unit_price), MAX(unit_price)
FROM public.online_retail_clean
WHERE stock_code IN ('22423', '85123A') AND unit_price > 0
GROUP BY stock_code;
-- =====================================================================
-- 4. DÉFINITION DU CHIFFRE D'AFFAIRES ET ÉVOLUTION MENSUELLE
-- =====================================================================

-- 4.0 Décomposition du CA hors copies : CA brut (ventes), retours (annulations), CA net après retours, frais et ajustements, et total de la table hors copies.
SELECT
    ROUND(SUM(montant) FILTER (WHERE type_ligne = 'vente'), 2)                       AS ca_brut_ventes,
    ROUND(SUM(montant) FILTER (WHERE type_ligne = 'annulation'), 2)                  AS retours,
    ROUND(SUM(montant) FILTER (WHERE type_ligne IN ('vente', 'annulation')), 2)      AS ca_net_apres_retours,
    ROUND(SUM(montant) FILTER (WHERE type_ligne NOT IN ('vente', 'annulation')), 2)  AS frais_et_ajustements,
    ROUND(SUM(montant), 2)                                                           AS total_table_hors_copies
FROM online_retail_clean
WHERE NOT is_doublon;

/*Après exclusion des doublons, le chiffre d’affaires brut des ventes s’élève à 10 247 219,32. Les retours et annulations représentent
-893 979,73, soit un CA net après retours de 9 353 239,59
Les frais et ajustements totalisent 372 767,36, portant le total des montants de la table à 9 726 006,95 */


-- 4.1 CA brut par mois (ventes hors copies) : CA, nombre de factures et panier moyen par facture.
-- Décembre 2010 est un mois complet, décembre 2011 est incomplet (les données s'arrêtent au 9 décembre).
SELECT
    DATE_TRUNC('month', invoice_date)::date              AS mois,
    ROUND(SUM(montant), 2)                               AS ca,
    COUNT(DISTINCT invoice_no)                           AS nb_factures,
    ROUND(SUM(montant) / COUNT(DISTINCT invoice_no), 0)  AS panier_moyen
FROM v_ventes
GROUP BY 1
ORDER BY 1;


-- =====================================================================
-- 5. ANALYSE DES MEILLEURS CLIENTS
-- =====================================================================

-- 5.1 CA généré et part du chiffre d'affaires

WITH v_ventes_nettes AS (
SELECT v.*
FROM v_ventes v
WHERE NOT EXISTS (
    SELECT 1
    FROM online_retail_clean a
    WHERE a.type_ligne = 'annulation'
      AND NOT a.is_doublon
      AND a.customer_id = v.customer_id
      AND a.montant = -v.montant
      AND a.invoice_date >= v.invoice_date
)
),
ca_par_client AS (
    SELECT
        customer_id,
        ROUND(SUM(montant), 2) AS ca_client,
        COUNT(DISTINCT invoice_no) AS nb_factures
    FROM v_ventes_nettes
    WHERE customer_id IS NOT NULL
    GROUP BY customer_id
),
totaux AS (
    SELECT
        SUM(montant) AS ca_total
    FROM v_ventes_nettes
),
ca_clients_identifies AS (
    SELECT
        SUM(ca_client) AS ca_clients_identifies
    FROM ca_par_client
)
SELECT
    c.customer_id,
    c.ca_client,
    c.nb_factures,
    ROUND(100.0 * c.ca_client / t.ca_total, 2) AS part_ca_total_pct,
    ROUND(100.0 * c.ca_client / i.ca_clients_identifies, 2) AS part_ca_clients_identifies_pct

FROM ca_par_client c
CROSS JOIN totaux t
CROSS JOIN ca_clients_identifies i
ORDER BY c.ca_client DESC
LIMIT 10;

/* Top 10 des clients par CA net : on retire d'abord les ventes annulées (rapprochées d'une annulation du même client, de montant opposé 
et postérieure), puis on calcule le CA par client identifié, son nombre de factures et sa part du CA total et du CA des clients identifiés. 
Les retours partiels ne sont pas déduits. */

-- 5.2 Part du CA associé aux lignes sans identifiant client
SELECT
    CASE
        WHEN customer_id IS NULL THEN 'Sans client identifié'
        ELSE 'Client identifié'
    END AS statut_client,

    COUNT(*) AS nb_lignes,

    ROUND(
        100.0 * COUNT(*) / SUM(COUNT(*)) OVER (),
        2
    ) AS part_lignes_pct,

    ROUND(SUM(montant), 2) AS ca,

    ROUND(
        100.0 * SUM(montant)
        / SUM(SUM(montant)) OVER (),
        2
    ) AS part_ca_pct

FROM v_ventes
GROUP BY
    CASE
        WHEN customer_id IS NULL THEN 'Sans client identifié'
        ELSE 'Client identifié'
    END
ORDER BY statut_client;



/* 25,14 % des lignes ne possèdent pas d'identifiant client, mais elles représentent 14,74 % du chiffre d'affaires total, soit 1 509 991,68.
Les clients identifiés représentent 74,86 % des lignes et génèrent 85,26 % du chiffre d'affaires, soit 8 737 227,64.
L'absence d'identifiant client limite l'analyse du comportement d'achat et la fidélisation de certains clients, malgré leur contribution
significative au chiffre d'affaires */


-- =====================================================================
-- 6. ANALYSE DES ANNULATIONS
-- =====================================================================


-- 6.1 Taux d'annulation : montant et nombre de factures
WITH indicateurs AS (
    SELECT
		DATE_TRUNC('month', invoice_date)::date AS mois,
        SUM(montant) FILTER (
            WHERE type_ligne = 'vente'
        ) AS ca_brut,
        SUM(montant) FILTER (
            WHERE type_ligne = 'annulation'
        ) AS montant_annulations,
        COUNT(DISTINCT invoice_no) FILTER (
            WHERE type_ligne = 'vente'
        ) AS nb_factures_ventes,
        COUNT(DISTINCT invoice_no) FILTER (
            WHERE type_ligne = 'annulation'
        ) AS nb_factures_annulees
    FROM online_retail_clean
    WHERE NOT is_doublon
	GROUP BY DATE_TRUNC('month', invoice_date)::date
)
SELECT mois,
    ROUND(ca_brut, 2) AS ca_brut,
    ROUND(montant_annulations, 2) AS montant_annulations,
    ROUND(100.0 * ABS(montant_annulations) / ca_brut, 2) AS taux_annulation_montant_pct,
    nb_factures_ventes,
    nb_factures_annulees,
    ROUND( 100.0 * nb_factures_annulees/ (nb_factures_ventes + nb_factures_annulees)) AS taux_factures_annulees_pct
FROM indicateurs
ORDER BY mois;


-- 6.2 calculs des KPIs

WITH indicateurs AS (
    SELECT
		ROUND(SUM(montant) FILTER (WHERE type_ligne IN ('vente', 'annulation')), 2)      AS ca_net_apres_retours,
        SUM(montant) FILTER (
            WHERE type_ligne = 'vente'
        ) AS ca_brut,
        SUM(montant) FILTER (
            WHERE type_ligne = 'annulation'
        ) AS montant_annulations,
        COUNT(DISTINCT invoice_no) FILTER (
            WHERE type_ligne = 'vente'
        ) AS nb_commandes,
		COUNT(DISTINCT invoice_no) FILTER (
            WHERE type_ligne = 'vente' AND customer_id IS NOT NULL
        ) AS nb_commandes_client,
        COUNT(DISTINCT customer_id) FILTER (
            WHERE type_ligne = 'vente'
              AND customer_id IS NOT NULL
        ) AS nb_clients
    FROM online_retail_clean
    WHERE NOT is_doublon
),

kpi AS (
    SELECT
        ca_brut,
		ca_net_apres_retours,
        montant_annulations,
        nb_commandes,
		nb_commandes_client,
        nb_clients
    FROM indicateurs
)

SELECT
	ca_brut,
	ca_net_apres_retours,
    ROUND(
        ca_brut / NULLIF(nb_commandes, 0),
        2
    ) AS panier_moyen,
    nb_commandes,
    nb_clients,
    ROUND(
        nb_commandes_client::numeric / NULLIF(nb_clients, 0),
        2
    ) AS frequence_achat,
    ROUND(
        100.0 * ABS(montant_annulations)
        / NULLIF(ca_brut, 0),
        2
    ) AS taux_annulation_pct
FROM kpi;

-- Rechercher des nouveaux clients

WITH premieres_commandes AS (
    SELECT
        customer_id,
        MIN(invoice_date) AS date_premiere_commande
    FROM online_retail_clean
    WHERE NOT is_doublon
      AND type_ligne = 'vente'
      AND customer_id IS NOT NULL
    GROUP BY customer_id
),

nouveaux_clients_mois AS (
    SELECT
        DATE_TRUNC('month', date_premiere_commande)::date AS mois,
        COUNT(*) AS nb_nouveaux_clients
    FROM premieres_commandes
    GROUP BY DATE_TRUNC('month', date_premiere_commande)::date
),

clients_actifs_mois AS (
    SELECT
        DATE_TRUNC('month', invoice_date)::date AS mois,
        COUNT(DISTINCT customer_id) AS nb_clients_actifs
    FROM online_retail_clean
    WHERE NOT is_doublon
      AND type_ligne = 'vente'
      AND customer_id IS NOT NULL
    GROUP BY DATE_TRUNC('month', invoice_date)::date
)

SELECT
    a.mois,
    COALESCE(n.nb_nouveaux_clients, 0) AS nb_nouveaux_clients,
    a.nb_clients_actifs,
    ROUND(
        100.0 * COALESCE(n.nb_nouveaux_clients, 0)
        / NULLIF(a.nb_clients_actifs, 0),
        2
    ) AS taux_nouveaux_clients_pct
FROM clients_actifs_mois a
LEFT JOIN nouveaux_clients_mois n
    ON a.mois = n.mois
ORDER BY a.mois;

-- Clients récurrents


WITH commandes_par_client AS (
    SELECT
        customer_id,
        COUNT(DISTINCT invoice_no) AS nb_commandes
    FROM online_retail_clean
    WHERE NOT is_doublon
      AND type_ligne = 'vente'
      AND customer_id IS NOT NULL
      AND invoice_date >= DATE '2011-01-01'
      AND invoice_date < DATE '2012-01-01'
    GROUP BY customer_id
),
categories AS (
    SELECT
        CASE
            WHEN nb_commandes = 1 THEN '1 commande'
            WHEN nb_commandes BETWEEN 2 AND 5 THEN '2 à 5 commandes'
            WHEN nb_commandes BETWEEN 6 AND 10 THEN '6 à 10 commandes'
            WHEN nb_commandes BETWEEN 11 AND 25 THEN '11 à 25 commandes'
            WHEN nb_commandes BETWEEN 26 AND 50 THEN '26 à 50 commandes'
            ELSE 'Plus de 50 commandes'
        END AS categorie,
        CASE
            WHEN nb_commandes = 1 THEN 1
            WHEN nb_commandes BETWEEN 2 AND 5 THEN 2
            WHEN nb_commandes BETWEEN 6 AND 10 THEN 3
            WHEN nb_commandes BETWEEN 11 AND 25 THEN 4
            WHEN nb_commandes BETWEEN 26 AND 50 THEN 5
            ELSE 6
        END AS ordre
    FROM commandes_par_client
),
repartition AS (
    SELECT
        categorie,
        ordre,
        COUNT(*) AS nb_clients
    FROM categories
    GROUP BY categorie, ordre
)
SELECT
    categorie,
    nb_clients,
    ROUND(
        100.0 * nb_clients / SUM(nb_clients) OVER (),
        2
    ) AS part_clients_pct
FROM repartition
ORDER BY ordre;


-- 6.3 Top 10 des produits ayant le montant d'annulation le plus élevé

SELECT
    stock_code,
    description,
    COUNT(*) AS nb_lignes_annulation,
    COUNT(DISTINCT invoice_no) AS nb_factures_annulation,
    SUM(ABS(quantity)) AS quantite_annulee,
    ROUND(SUM(ABS(montant)), 2) AS montant_annulations
FROM online_retail_clean
WHERE NOT is_doublon
  AND type_ligne = 'annulation'
GROUP BY
    stock_code,
    description
ORDER BY montant_annulations DESC
LIMIT 10;


-- 6.4 Top 10 des produits physiques selon le montant annulé
SELECT
    stock_code,
    description,
    COUNT(*) AS nb_lignes_annulation,
    COUNT(DISTINCT invoice_no) AS nb_factures_annulation,
    SUM(ABS(quantity)) AS quantite_annulee,
    ROUND(SUM(ABS(montant)), 2) AS montant_annulations
FROM online_retail_clean
WHERE NOT is_doublon
  AND type_ligne = 'annulation'
  AND stock_code NOT IN ('AMAZONFEE','M','D','S','POST','CRUK', 'BANK CHARGES')
GROUP BY stock_code, description
ORDER BY montant_annulations DESC
LIMIT 10;

/* Deux produits dominent les annulations : 23843 (80 995 unités, 168 469,60) et 23166 (74 494 unités, 77 479,64), avec une seule facture 
d'annulation pour le premier. Ces valeurs exceptionnelles sont vérifiées en 6.4. */
   
-- 6.5 Vérifier les quantités et montants annulés anormalement élevés
SELECT
    invoice_no,
    invoice_date,
    stock_code,
    description,
    quantity,
    montant,unit_price,
    customer_id
FROM online_retail_clean
WHERE NOT is_doublon
  AND type_ligne IN ('vente','annulation')
  AND stock_code IN ('23843', '23166')
ORDER BY ABS(quantity) DESC;

/*Conclusion : Les quantités exceptionnellement élevées détectées pour deux produits correspondent à des ventes suivies d'annulations 
intégrales quelques minutes plus tard. Les montants et les quantités se compensent exactement : leur impact net sur le CA est nul.
Ces opérations doivent être distinguées des retours partiels dans l'analyse.*/

-- 6.6 Top 10 des produits physiques retournés sans les quantités exceptionnellement élevées

SELECT
    stock_code,
    description,
    COUNT(*) AS nb_lignes_annulation,
    COUNT(DISTINCT invoice_no) AS nb_factures_annulation,
    SUM(ABS(quantity)) AS quantite_annulee,
    ROUND(SUM(ABS(montant)), 2) AS montant_annulations
FROM online_retail_clean
WHERE NOT is_doublon
  AND type_ligne = 'annulation'
  AND stock_code NOT IN ('AMAZONFEE','M','D','S','POST','CRUK', 'BANK CHARGES','23843','23166')
GROUP BY stock_code, description
ORDER BY montant_annulations DESC
LIMIT 10;

/* Top 10 des produits les plus annulés, hors les deux cas exceptionnels 23843 et 23166 (vente annulée en bloc, cf. 6.4).
REGENCY CAKESTAND 3 TIER est le plus annulé (9 697,05 sur 180 factures, 855 unités), devant WHITE HANGING HEART T-LIGHT HOLDER (6 624,30). 
Ce sont aussi deux des produits les plus vendus : leurs annulations restent faibles par rapport à leur CA. Les autres montants sont inférieurs à 6 600. */