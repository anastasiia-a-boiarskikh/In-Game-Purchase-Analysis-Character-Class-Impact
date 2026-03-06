/* Проект «Секреты Тёмнолесья»
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей 
 * на покупку внутриигровой валюты «райские лепестки», а также оценить 
 * активность игроков при совершении внутриигровых покупок
*/

-- Часть 1. Исследовательский анализ данных
-- Задача 1. Исследование доли платящих игроков

-- 1.1. Доля платящих пользователей по всем данным:

SELECT
	-- используем DISTINCT для подсчета уникальных id 
	-- корректировка: в таблице нет дубликатов, поэтому использоват не нужно
	COUNT(id) AS total_users,
	-- у платящих пользователей значение поля payer равно 1 -- корректировка: не используем DISTINCT, т.к. в таблице нет дубликатов
	COUNT(CASE WHEN payer=1 THEN id END) AS paying_users,
	-- считаем процент платящих пользователей, т.к. процент воспринимается легче, чем соотношение; округляем
	ROUND(100 * COUNT(DISTINCT CASE WHEN payer=1 THEN id END) / CAST(COUNT(DISTINCT id) AS NUMERIC), 2) AS paying_users_percent
FROM fantasy.users;

-- 1.2. Доля платящих пользователей в разрезе расы персонажа:

SELECT 
	r.race,
	COUNT(CASE WHEN payer=1 THEN u.id END) AS paying_users_per_race,
	COUNT(CASE WHEN payer IS NOT NULL THEN u.id END) AS total_users_per_race,
	ROUND(100 * CAST(COUNT(DISTINCT CASE WHEN payer=1 THEN u.id END) AS NUMERIC) / COUNT(CASE WHEN payer IS NOT NULL THEN u.id END), 2) AS paying_users_per_race_percent
-- объединим таблицы, чтобы в выгрузке видеть более понятное race, а не race_id
FROM fantasy.users AS u 
JOIN fantasy.race AS r USING(race_id)
GROUP BY race
ORDER BY paying_users_per_race_percent DESC;
	

-- Задача 2. Исследование внутриигровых покупок
-- 2.1. Статистические показатели по полю amount:

SELECT
	COUNT(transaction_id) AS total_purchases,
	SUM(amount) AS total_revenue,
	MIN(amount) AS min_cost,
	MAX(amount) AS max_cost,
	-- можем округлить до целых, поскольку значение порядка сотен
	ROUND(AVG(amount)) AS avg_cost,
	-- можем округлить до целых, поскольку значение порядка тысяч
	ROUND(STDDEV(amount)) AS st_dev_cost,
	-- значений в таблице много, поэтому может применить дискретную функцию
	ROUND(PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY amount)) AS median_cost_disc
FROM fantasy.events
WHERE amount <> 0;

-- судя по значению описательных статистик, данное распределение не является нормальным, поэтому лучше описать его не средним и стандартным отклонением, а процентилями 
SELECT 
	ROUND(PERCENTILE_DISC(0.25) WITHIN GROUP (ORDER BY amount)) AS perc_25,
	ROUND(PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY amount)) AS median,
	ROUND(PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY amount)) AS perc_75
FROM fantasy.events
-- корректировка: исключены записи с amount=0
WHERE amount <> 0;

-- еще интересно посмотреть на значение, менее которого значения 95% выборки
SELECT 
	ROUND(PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY amount)) AS perc_95
FROM fantasy.events
-- корректировка: исключены записи с amount=0
WHERE amount <> 0;

-- 2.2: Аномальные нулевые покупки:

-- можно сразу отметить, что покупки с нулевой стоимостью есть, т.к. в предыдущем блоке минимальное значение по полю amount было равно 0
-- посчитаем кол-во таких покупок

SELECT 
	COUNT(CASE WHEN amount=0 THEN transaction_id END) AS null_cost_count,
	ROUND(100*CAST(COUNT(CASE WHEN amount=0 THEN transaction_id END) AS NUMERIC)/COUNT(transaction_id), 2) AS null_cost_percent
FROM fantasy.events;

-- дополнительный запрос для проверки того, какие пользователи генерируют транзакции с нулевой стоимостью
SELECT
	id AS users_with_zero_amount_transactions,
	COUNT(id) AS number_of_zero_amount_transactions
FROM fantasy.events
WHERE amount=0
GROUP BY id
ORDER BY number_of_zero_amount_transactions DESC;

-- 2.3: Сравнительный анализ активности платящих и неплатящих игроков:

-- к таблице events присоединю таблицу users, чтобы добавить инф-ю о том, является ли игрок платящим
WITH connected_events_users AS (
	SELECT
		e.transaction_id,
		e.id,
		e.amount,
		u.payer
	FROM fantasy.events AS e
	LEFT JOIN fantasy.users AS u USING(id)
)

-- среднее буду считать как сумму по всем игрокам категории (платящий / не платящий), раделенную на кол-во игроков категории
-- название категории добавляю просто для удобства чтения вывода
SELECT
	CASE
		WHEN payer = 0 THEN 'non-payer'
		WHEN payer = 1 THEN 'payer'
	END AS category,
	-- использую DISTINCT, т.к. в таблице events пользователи могут встречаться более 1 раза
	COUNT(DISTINCT id) AS total_users,
	COUNT(transaction_id) / COUNT(DISTINCT id) AS avg_purchase_count,
	ROUND(SUM(amount) / COUNT(DISTINCT id)) AS avg_amount
FROM connected_events_users
-- не учитываем покупки с нулевой стоимостью
WHERE amount <> 0
GROUP BY payer;

-- 2.4: Популярные эпические предметы:

WITH main_table AS (
	SELECT
		item_code,
		COUNT(transaction_id) AS absolute_purchase_count,
		-- фильтрация покупок с нулевой стоимостью в подзапросах
		100*CAST(COUNT(transaction_id) AS NUMERIC) / (SELECT COUNT(transaction_id) FROM fantasy.events WHERE amount <> 0) AS share_purchase_count,
		-- посчитала долю от игроков, совершавших покупки (использовала таблицу events, а не users)
		100*CAST(COUNT(DISTINCT id) AS NUMERIC) / (SELECT COUNT(DISTINCT id) FROM fantasy.events WHERE amount <> 0) AS users_share
	FROM fantasy.events
	WHERE amount <> 0
	GROUP BY item_code
)

SELECT
	i.game_items, 
	COALESCE(ROUND(m.absolute_purchase_count, 1), 0) AS absolute_purchase_count,
	COALESCE(ROUND(m.share_purchase_count, 1), 0) AS share_purchase_count,
	COALESCE(ROUND(m.users_share, 2), 0) AS users_share
FROM main_table AS m
-- использовала outer join при присоединении, т.к. не все предметы могли покупать, но по заданию посчитать нужно "для каждого предмета"
FULL JOIN fantasy.items AS i USING(item_code)
ORDER BY users_share DESC;

SELECT
	game_items, 
	COALESCE(ROUND(COUNT(transaction_id), 1), 0) AS absolute_purchase_count,
	COALESCE(ROUND(100*CAST(COUNT(transaction_id) AS NUMERIC) / SUM(COUNT(transaction_id)) OVER(), 1), 0) AS share_purchase_count,
	COALESCE(ROUND(100*CAST(COUNT(DISTINCT id) AS NUMERIC) / (SELECT COUNT(DISTINCT id) FROM fantasy.events WHERE amount <> 0), 2), 0) AS users_share
FROM fantasy.events
-- использовала outer join при присоединении, т.к. не все предметы могли покупать, но по заданию посчитать нужно "для каждого предмета"
FULL JOIN fantasy.items USING(item_code)
WHERE amount <> 0
GROUP BY game_items
ORDER BY users_share DESC;

-- Часть 2. Решение ad hoc-задач
-- Задача 1. Зависимость активности игроков от расы персонажа:

WITH 

total_users_count AS (
	SELECT 
		race_id,
		COUNT(id) AS total_players
	FROM fantasy.users
	GROUP BY race_id
),

users_pay_in_game_count AS (
	SELECT 
		race_id,
		COUNT(id) AS users_pay_in_game,
		-- доля платящих игроков от количества игроков, которые совершили покупки
		CAST(COUNT(CASE WHEN payer=1 THEN id END) AS NUMERIC) / COUNT(id) AS paying_users_share
	FROM fantasy.users
	WHERE id IN (
		-- не учитываем покупки с нулевой стоимостью 
		SELECT DISTINCT (id) FROM fantasy.events WHERE amount <> 0)
	GROUP BY race_id
),

averages_count AS (
	SELECT
		race_id,
		-- посчитала средние не по всем игрокам, а только по тем, кто совершал внутриигровые покупки
		COUNT(transaction_id) / COUNT(DISTINCT id) AS avg_purcases_per_user,
		SUM(amount) / COUNT(transaction_id) AS avg_one_purcase_amount,
		SUM(amount) / COUNT(DISTINCT id) AS avg_one_user_amount
	FROM fantasy.events AS e
	LEFT JOIN fantasy.users AS u USING(id)
	WHERE amount <> 0
	GROUP BY race_id
)


SELECT 
	r.race,
	t.total_players,
	p.users_pay_in_game,
	-- доля игроков, которые совершают внутриигровые покупки, от общего количества игроков
	ROUND(100*CAST(p.users_pay_in_game AS NUMERIC) / t.total_players, 2) AS users_pay_in_game_share,
	ROUND(100*p.paying_users_share, 2) AS paying_users_share,
	a.avg_purcases_per_user,
	ROUND(a.avg_one_purcase_amount) AS avg_one_purcase_amount,
	ROUND(a.avg_one_user_amount) AS avg_one_user_amount
FROM total_users_count AS t
JOIN users_pay_in_game_count AS p USING(race_id)
JOIN averages_count AS a USING(race_id)
JOIN fantasy.race AS r USING(race_id)
ORDER BY avg_purcases_per_user DESC;

