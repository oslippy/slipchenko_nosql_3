// Частина 2 — завантаження MovieLens у Neo4j.
// Що робить кожен запит і чому саме так — пояснено в README.
// Запуск: cypher-shell -u neo4j -p password123 -f part2_load.cypher

// Крок 0. Обмеження унікальності (одразу дають потрібні індекси)
CREATE CONSTRAINT user_id  IF NOT EXISTS FOR (u:User)  REQUIRE u.userId  IS UNIQUE;
CREATE CONSTRAINT movie_id IF NOT EXISTS FOR (m:Movie) REQUIRE m.movieId IS UNIQUE;
CREATE CONSTRAINT genre_nm IF NOT EXISTS FOR (g:Genre) REQUIRE g.name    IS UNIQUE;

// Крок 1. Вузли User
LOAD CSV WITH HEADERS FROM 'file:///users.csv' AS row
MERGE (u:User {userId: toInteger(row.userId)})
SET u.gender     = row.gender,
    u.age        = toInteger(row.age),
    u.occupation = toInteger(row.occupation);

// Крок 2. Вузли Movie + Genre + ребра HAS_GENRE
LOAD CSV WITH HEADERS FROM 'file:///movies.csv' AS row
MERGE (m:Movie {movieId: toInteger(row.movieId)})
SET m.title = row.title,
    m.year  = toInteger(substring(row.title, size(row.title) - 5, 4))
WITH m, row
UNWIND split(row.genres, '|') AS genreName
MERGE (g:Genre {name: genreName})
MERGE (m)-[:HAS_GENRE]->(g);

// Крок 3. Індекси вже створені обмеженнями з кроку 0 — окремих не треба.

// Крок 4. Ребра RATED — батчами, бо їх понад мільйон
CALL apoc.periodic.iterate(
  'LOAD CSV WITH HEADERS FROM "file:///ratings.csv" AS row RETURN row',
  'MATCH (u:User  {userId:  toInteger(row.userId)})
   MATCH (m:Movie {movieId: toInteger(row.movieId)})
   MERGE (u)-[r:RATED]->(m)
   SET r.rating    = toInteger(row.rating),
       r.timestamp = toInteger(row.timestamp)',
  {batchSize: 10000, parallel: false}
);

// Крок 5. Перевірка
MATCH (u:User)         RETURN count(u) AS users;
MATCH (m:Movie)        RETURN count(m) AS movies;
MATCH (g:Genre)        RETURN count(g) AS genres;
MATCH ()-[r:RATED]->() RETURN count(r) AS ratings;
