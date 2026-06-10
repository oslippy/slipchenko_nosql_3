// Частина 4 — виявлення супервузлів.
// Що робить кожен запит і чому саме так — пояснено в README.

// Запит 1. Розподіл степеня по типах вузлів — що взагалі вважати нормою
MATCH (n)
WITH labels(n)[0] AS label, COUNT { (n)--() } AS degree
RETURN label, count(*) AS nodes,
       min(degree) AS min_deg, round(avg(degree)) AS avg_deg, max(degree) AS max_deg
ORDER BY max_deg DESC;

// Запит 2. Самі супервузли — топ-15 за кількістю зв'язків
MATCH (n)
WITH n, COUNT { (n)--() } AS degree
ORDER BY degree DESC
LIMIT 15
RETURN labels(n)[0] AS label,
       coalesce(n.title, n.name, 'user ' + toString(n.userId)) AS node,
       degree;

// Запит 3. Чи є супервузлами жанри — степінь кожного жанру
MATCH (g:Genre)
RETURN g.name AS genre, COUNT { (g)<-[:HAS_GENRE]-() } AS movies
ORDER BY movies DESC;
