# Analyse des ventes d'une boutique en ligne (SQL / PostgreSQL)

## Objectif
Nettoyer et analyser les transactions d'une boutique en ligne pour mesurer le chiffre d'affaires
(brut et net), identifier les pays, produits et clients clés, et quantifier les annulations.

## Données
- Jeu « Online Retail » (UCI) : 541 909 lignes de transactions, du 01/12/2010 au 09/12/2011
  (décembre 2011 incomplet).
- Colonnes : facture, code produit, description, quantité, date, prix unitaire, client, pays.
NB : Le fichier « Online Retail » n'est pas inclus dans le dépôt (taille). Il est téléchargeable gratuitement sur le site de l'UCI Machine Learning Repository (https://archive.ics.uci.edu/dataset/352/online+retail). Le script SQL le charge puis construit la table nettoyée.

## Outils
PostgreSQL (pgAdmin) : CTE, fonctions de fenêtre, agrégats filtrés, expressions régulières, jointures latérales.

## Démarche
1. **Mise en place** : import du CSV en texte brut, puis conversion des types.
2. **Audit de la table brute** : période, valeurs manquantes, quantités ou prix anormaux, codes spéciaux. Chaque ligne est classée dans une catégorie, et le total retrouvé (541 909 lignes, 9 747 747,93) sert de contrôle.
3. **Nettoyage sans suppression** : table `online_retail_clean` avec dates converties, montant calculé, type de ligne (vente, annulation, frais, ajustements) et marquage des doublons (`is_doublon`). La table brute reste intacte.
4. **Vue d'analyse** : `v_ventes` (ventes sans doublons) sert de base aux analyses.
5. **Contrôles de qualité** : doublons, libellés multiples, formats de codes produit, prix atypiques.
6. **Analyses business** : CA par pays, top produits (brut puis net des annulations).
7. **Définition du CA** : CA brut, retours, CA net, frais et ajustements.
8. **Évolution mensuelle** : CA, nombre de factures, panier moyen.
9. **Meilleurs clients** : CA par client, part des lignes sans identifiant.
10. **Annulations** : taux, produits les plus annulés, cas de grosses ventes annulées.

## Résultats clés
| Indicateur | Valeur |
|---|---|
| Base d'analyse | 522 537 lignes, 19 773 factures, 4 334 clients, 3 798 produits, 38 pays |
| CA brut des ventes | 10 247 219,32 |
| Retours / annulations | -893 979,73 (≈ 8,7 % du CA brut) |
| CA net après retours | 9 353 239,59 |
| Poids du Royaume-Uni | 85,1 % du CA |
| Lignes sans client | 25,1 % des lignes, 14,7 % du CA |
| Top produit (CA net) | REGENCY CAKESTAND 3 TIER (161 963,94) |

## Choix méthodologiques
- **Doublons** : 5 268 lignes strictement identiques sur les 8 colonnes, marquées et non supprimées. Parmi les ventes, 5 221 doublons pèsent 0,24 % du CA. Exclusion retenue par prudence, et réversible.
- **Codes produit** : analyse par `stock_code`, avec la description la plus fréquente comme libellé (212 codes ont plusieurs descriptions, le plus souvent des variantes d'écriture).
Les 16 codes qui ne sont pas des produits (frais, saisies manuelles) sont exclus du top produits.
- **Prix atypiques** : 55 codes ont un prix maximum supérieur à 10 fois leur médiane, pour au plus 1 % du CA. Impact jugé négligeable.
- **Ventes annulées** : le top produits net écarte les ventes annulées, rapprochées de leur annulation par client et montant opposé.

## Conclusions

1. **Chiffre d'affaires** : 10,25 M de CA brut, 9,35 M après retours (-0,89 M, soit 8,7 % du CA brut).
2. **Marché** : le Royaume-Uni génère 85,1 % du CA, ce qui rend l'activité très dépendante d'un seul pays.
3. **Produits** : le REGENCY CAKESTAND 3 TIER est le premier produit en CA net (161 964), devant le WHITE HANGING HEART T-LIGHT HOLDER (99 081).
4. **Clients** : 25 % des lignes n'ont pas d'identifiant client (15 % du CA). Le classement des clients est à lire avec prudence, car deux clients du top 10 doivent leur rang à une vente entièrement annulée ensuite.
5. **Annulations** : elles sont dominées par deux cas exceptionnels, des ventes annulées en bloc quelques minutes plus tard (produits 23843 et 23166). Hors ces cas, le produit le plus annulé reste le REGENCY CAKESTAND, sans impact notable par rapport à son CA.
6. **Qualité des données** : doublons (0,24 % du CA), libellés multiples et prix atypiques (au plus 1 % du CA) ont un impact négligeable sur les résultats.

## Limites
- Le rapprochement vente/annulation est approximatif, et les ventes sans client ne sont jamais rapprochées.
- Le CA brut inclut quelques ventes de très forte valeur entièrement annulées ensuite ; le CA net en tient compte.
- Un quart des lignes n'a pas d'identifiant client, ce qui limite l'analyse des comportements d'achat.
- Une seule année de données, avec un dernier mois incomplet.

## Fichier
`projet_sql_online_retail.sql` : script complet, exécutable dans l'ordre (sections 0 à 6),
chaque requête étant commentée.
