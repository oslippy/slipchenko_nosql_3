// Частина 5 — графові алгоритми через GDS (версія 2.6.9).
// Що робить кожен запит і чому саме так — пояснено в README.
// Перед алгоритмом потрібна проєкція графа в пам'ять GDS — це окремий крок.


// ============================================================
// 5.1. PageRank на графі фільмів
// ============================================================

// Крок 1: матеріалізуємо ребра фільм-фільм через спільних користувачів
MATCH (m1:Movie)<-[r1:RATED]-(u:User)-[r2:RATED]->(m2:Movie)
WHERE r1.rating >= 4 AND r2.rating >= 4 AND id(m1) < id(m2)
WITH m1, m2, count(u) AS weight
WHERE size([(m1)<-[:RATED]-() | 1]) > 20
  AND size([(m2)<-[:RATED]-() | 1]) > 20
WITH m1, m2, weight
ORDER BY weight DESC
LIMIT 50000
MERGE (m1)-[co:CO_RATED]-(m2)
SET co.weight = weight;

// Крок 2: створюємо проєкцію на основі матеріалізованих ребер
CALL gds.graph.project(
  'movieGraph',
  'Movie',
  { CO_RATED: { orientation: 'UNDIRECTED', properties: 'weight' } }
)
YIELD graphName, nodeCount, relationshipCount;

// Крок 3: PageRank на цьому графі, топ-15 фільмів.
// num_ratings показую поряд, щоб порівняти ранг із простою популярністю.
CALL gds.pageRank.stream('movieGraph', { relationshipWeightProperty: 'weight' })
YIELD nodeId, score
WITH gds.util.asNode(nodeId) AS m, score
RETURN m.title AS movie,
       round(score, 3) AS pagerank,
       size([(m)<-[:RATED]-() | 1]) AS num_ratings
ORDER BY pagerank DESC
LIMIT 15;

// Крок 4: видаляємо проєкцію та тимчасові ребра
CALL gds.graph.drop('movieGraph');
MATCH ()-[co:CO_RATED]-() DELETE co;


// ============================================================
// 5.2. Виявлення спільнот (Louvain)
// ============================================================

// Крок 1: матеріалізуємо ребра користувач-користувач через спільні фільми.
// Поріг = 5 (а не >= 4): пар користувачів набагато більше, ніж пар
// фільмів, і на >= 4 матеріалізація не вкладається в пам'ять транзакції.
MATCH (u1:User)-[r1:RATED]->(m:Movie)<-[r2:RATED]-(u2:User)
WHERE r1.rating = 5 AND r2.rating = 5 AND id(u1) < id(u2)
WITH u1, u2, count(m) AS weight
WITH u1, u2, weight
ORDER BY weight DESC
LIMIT 50000
MERGE (u1)-[sim:SIMILAR]-(u2)
SET sim.weight = weight;

// Крок 2: створюємо проєкцію
CALL gds.graph.project(
  'userSimilarity',
  'User',
  { SIMILAR: { orientation: 'UNDIRECTED', properties: 'weight' } }
)
YIELD graphName, nodeCount, relationshipCount;

// Крок 3: Louvain — записуємо спільноту кожного користувача у властивість.
// modularity показує якість розбиття.
CALL gds.louvain.write('userSimilarity', {
  relationshipWeightProperty: 'weight',
  writeProperty: 'community'
})
YIELD communityCount, modularity;

// 10 найбільших спільнот (одинаків без сусідів відкидаємо)
MATCH (u:User) WHERE u.community IS NOT NULL
WITH u.community AS community, count(*) AS size
WHERE size > 1
RETURN community, size
ORDER BY size DESC
LIMIT 10;

// Крок 4: три найпопулярніші жанри для кожної з найбільших спільнот
MATCH (u:User) WHERE u.community IS NOT NULL
WITH u.community AS community, count(*) AS size
WHERE size > 1
WITH community ORDER BY size DESC LIMIT 10
WITH collect(community) AS top
MATCH (u:User)-[r:RATED]->(:Movie)-[:HAS_GENRE]->(g:Genre)
WHERE u.community IN top AND r.rating >= 4
WITH u.community AS community, g.name AS genre, count(*) AS cnt
ORDER BY community, cnt DESC
WITH community, collect(genre)[0..3] AS top3_genres
RETURN community, top3_genres
ORDER BY community;

// Аналіз: сирий топ-3 у всіх схожий (домінують Drama/Comedy), тому рахую
// lift = частка жанру в кластері / його глобальна частка. Над-представлені
// жанри й показують реальний нахил смаку кожної спільноти.
MATCH (:User)-[r:RATED]->(:Movie)-[:HAS_GENRE]->(g:Genre) WHERE r.rating >= 4
WITH g.name AS genre, toFloat(count(*)) AS c
WITH collect({g: genre, c: c}) AS rows, sum(c) AS total
WITH apoc.map.fromPairs([x IN rows | [x.g, x.c / total]]) AS globalShare
MATCH (u:User) WHERE u.community IS NOT NULL
WITH globalShare, u.community AS community, count(*) AS size
WHERE size > 1
WITH globalShare, community ORDER BY size DESC LIMIT 10
WITH globalShare, collect(community) AS top
MATCH (u:User)-[r:RATED]->(:Movie)-[:HAS_GENRE]->(g:Genre)
WHERE u.community IN top AND r.rating >= 4
WITH globalShare, u.community AS community, g.name AS genre, toFloat(count(*)) AS c
WITH globalShare, community, collect({g: genre, c: c}) AS rows, sum(c) AS ctot
UNWIND rows AS row
WITH community, row.g AS genre, round((row.c / ctot) / globalShare[row.g], 2) AS lift
ORDER BY community, lift DESC
WITH community, collect(genre + ' x' + toString(lift)) AS lifted
RETURN community, lifted[0..4] AS over_represented
ORDER BY community;

// Крок 5: видаляємо проєкцію, тимчасові ребра та властивість community
CALL gds.graph.drop('userSimilarity');
MATCH ()-[sim:SIMILAR]-() DELETE sim;
MATCH (u:User) WHERE u.community IS NOT NULL REMOVE u.community;


// ============================================================
// 5.3. Найкоротший шлях між користувачами (Дейкстра)
// ============================================================

// Проєкція потрібна та сама, що і для Louvain — створюємо заново (поріг = 5)
MATCH (u1:User)-[r1:RATED]->(m:Movie)<-[r2:RATED]-(u2:User)
WHERE r1.rating = 5 AND r2.rating = 5 AND id(u1) < id(u2)
WITH u1, u2, count(m) AS weight
WITH u1, u2, weight
ORDER BY weight DESC
LIMIT 50000
MERGE (u1)-[sim:SIMILAR]-(u2)
SET sim.weight = weight;

CALL gds.graph.project(
  'userGraph',
  'User',
  { SIMILAR: { orientation: 'UNDIRECTED', properties: 'weight' } }
)
YIELD graphName, nodeCount, relationshipCount;

// Крок 3: Дейкстра для кількох пар. Вагу НЕ передаю: weight = кількість
// спільних фільмів — це близькість, а не відстань. Для «тісного світу»
// важлива кількість ланок, тож рахуємо хопи (Дейкстра по вазі 1.0).
UNWIND [[17, 33], [17, 27], [10, 58], [81, 175], [34, 44]] AS pair
MATCH (s:User {userId: pair[0]}), (t:User {userId: pair[1]})
CALL {
  WITH s, t
  CALL gds.shortestPath.dijkstra.stream('userGraph', { sourceNode: s, targetNode: t })
  YIELD totalCost
  RETURN totalCost
}
RETURN pair[0] AS src, pair[1] AS tgt, toInteger(totalCost) AS hops;

// Середня та максимальна довжина шляху від кількох джерел до всіх досяжних
UNWIND [17, 81, 10, 58] AS sid
MATCH (s:User {userId: sid})
CALL {
  WITH s
  CALL gds.allShortestPaths.dijkstra.stream('userGraph', { sourceNode: s })
  YIELD totalCost
  WITH totalCost WHERE totalCost > 0
  RETURN round(avg(totalCost), 2) AS avg_hops,
         toInteger(max(totalCost)) AS max_hops,
         count(*) AS reachable
}
RETURN sid AS source, avg_hops, max_hops, reachable;

// Прибирання: проєкція та тимчасові ребра
CALL gds.graph.drop('userGraph');
MATCH ()-[sim:SIMILAR]-() DELETE sim;
