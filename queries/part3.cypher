// Частина 3 — запити різної складності.
// Що робить кожен запит і чому саме так — пояснено в README.

// Запит 1. Фільми жанру Thriller із середнім рейтингом вище 4.0
MATCH (:Genre {name: 'Thriller'})<-[:HAS_GENRE]-(m:Movie)<-[r:RATED]-()
WITH m, avg(r.rating) AS avg_rating, count(r) AS num_ratings
WHERE avg_rating > 4.0
RETURN m.title AS movie, round(avg_rating, 2) AS avg_rating, num_ratings
ORDER BY avg_rating DESC;

// Запит 2. Користувачі, що поставили оцінку 5 більш ніж 50 фільмам
MATCH (u:User)-[r:RATED]->(:Movie)
WHERE r.rating = 5
WITH u, count(r) AS fives
WHERE fives > 50
RETURN u.userId AS user_id, fives
ORDER BY fives DESC;

// Запит 3. Фільми, які і user 1, і user 2 оцінили високо (рейтинг >= 4)
MATCH (u1:User {userId: 1})-[r1:RATED]->(m:Movie)<-[r2:RATED]-(u2:User {userId: 2})
WHERE r1.rating >= 4 AND r2.rating >= 4
RETURN m.title AS movie, r1.rating AS rating_u1, r2.rating AS rating_u2
ORDER BY m.title;

// Запит 4. Жанри за середнім рейтингом і кількістю оцінок
MATCH (g:Genre)<-[:HAS_GENRE]-(:Movie)<-[r:RATED]-()
WITH g, avg(r.rating) AS avg_rating, count(r) AS num_ratings
RETURN g.name AS genre, round(avg_rating, 3) AS avg_rating, num_ratings
ORDER BY avg_rating DESC;

// Запит 5. Рекомендації для user 1 від користувачів зі схожим смаком
MATCH (me:User {userId: 1})-[r1:RATED]->(common:Movie)<-[r2:RATED]-(other:User)
WHERE r1.rating >= 4 AND r2.rating >= 4 AND me <> other
WITH me, other, count(common) AS shared_taste
ORDER BY shared_taste DESC
LIMIT 50
MATCH (other)-[r3:RATED]->(rec:Movie)
WHERE r3.rating >= 4 AND NOT EXISTS { (me)-[:RATED]->(rec) }
RETURN rec.title AS recommendation,
       count(DISTINCT other) AS recommended_by,
       round(avg(r3.rating), 2) AS avg_rating
ORDER BY recommended_by DESC, avg_rating DESC
LIMIT 10;

// Запит 6. Найкоротший ланцюжок між двома користувачами через спільні фільми
MATCH path = shortestPath(
  (a:User {userId: 1})-[:RATED*..10]-(b:User {userId: 2})
)
RETURN length(path) AS hops,
       [n IN nodes(path) |
         CASE WHEN n:User THEN 'User#' + toString(n.userId) ELSE n.title END] AS chain;
