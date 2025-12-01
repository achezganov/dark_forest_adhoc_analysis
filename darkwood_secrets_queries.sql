/* Проект «Секреты Тёмнолесья»
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей 
 * на покупку внутриигровой валюты «райские лепестки», а также оценить 
 * активность игроков при совершении внутриигровых покупок
 * 
 * Автор: Чезганов Алексей
 * Дата: 1.12.25 (дата редакции)
*/

-- Часть 1. Исследовательский анализ данных
-- Задача 1. Исследование доли платящих игроков

-- 1.1. Доля платящих пользователей по всем данным:

-- Т.к. в поле "payer" значения либо 0, либо 1, можно использовать в качестве подсчета среднее значение.
SELECT
    COUNT(*) AS total_players, -- всего игроков
    SUM(payer) AS total_payers, -- всего плательщиков
    ROUND(AVG(payer), 4) * 100 AS share_of_payers -- доля плательщиков
FROM fantasy.users;

-- 1.2. Доля платящих пользователей в разрезе расы персонажа:

SELECT
    *,
    ROUND(payers_percent * race_shape, 2) AS total_percent -- % расы в общей массе игроков
FROM (
    SELECT
        r.race,
        COUNT(*)                                                               AS players_per_race, -- кол-во игроков в расе
        SUM(u.payer)                                                           AS payers_per_race, -- кол-во плательщиков в расе
        ROUND( SUM(u.payer) / COUNT(*)::numeric, 4 ) * 100                     AS payers_percent, -- % плательщиков расы
        ROUND( COUNT(*)::numeric / ( SELECT COUNT(*) FROM fantasy.users ), 4 ) AS race_shape -- доля всех пользователей расы
    FROM fantasy.users    AS u
        JOIN fantasy.race AS r USING(race_id)
    GROUP BY r.race)
AS races_shape
ORDER BY payers_percent DESC;

-- Задача 2. Исследование внутриигровых покупок
-- 2.1. Статистические показатели по полю amount:

SELECT DISTINCT
    COUNT(*)                                                  AS total_purchases, -- общее кол-во покупок
    SUM(amount)                                               AS total_turnover, -- оборот "райских лепестков"
    MAX(amount)                                               AS max_amount, -- максимальная транзакция
    MIN(amount)                                               AS min_amount, -- минимальная транзакция
    (SELECT MIN(amount) FROM fantasy.events WHERE amount > 0) AS min_non_zero_amount, -- мин. без нулевых покупок
    AVG(amount)                                               AS avg_amount, -- среднее значение транзакции
    STDDEV(amount)                                            AS standard_deviation, -- стандартное отклонение
    PERCENTILE_DISC(0.25) WITHIN GROUP ( ORDER BY amount )    AS q1, -- 1-ый квартиль
    PERCENTILE_DISC(0.5) WITHIN GROUP ( ORDER BY amount )     AS q2, -- 2-ой квартиль, медиана
    PERCENTILE_DISC(0.75) WITHIN GROUP ( ORDER BY amount )    AS q3  -- 3-ий квартиль
FROM fantasy.events;

-- 2.2: Аномальные нулевые покупки:

SELECT
    COUNT(*) AS total_purchases, -- всего покупок
    SUM( CASE WHEN amount = 0 THEN 1 ELSE 0 END ) AS zero_amt_count, -- кол-во покупок с 0 ценой
    ROUND( SUM( CASE WHEN amount = 0 THEN 1 ELSE 0 END )::numeric / COUNT(*), 4 ) * 100 AS zero_amt_share_percent -- доля
                                                                                                    -- от всех покупок
FROM fantasy.events;

-- Запрос показывает id игрока и то, сколько он совершил покупок с нулевой стоимостью.
SELECT
    id,
    COUNT(*) AS count_of_zero_amt_per_player -- количество покупок с нулевой стоимостью у игрока
FROM fantasy.events
WHERE amount = 0
GROUP BY id
ORDER BY count_of_zero_amt_per_player DESC;

-- Запрос демонстрирует, что всего 907 "нулевых" покупок, в частности видно, что покупали только 1 предмет,
-- либо это акция, что требует дополнительного анализа, можно смотреть как распределяются выбросы на протяжении времени,
-- либо предмет вовсе бесплатный или был им.

SELECT
    i.game_items, -- название предмета
    CASE
        WHEN e.seller_id IS NOT NULL THEN 'exists'
        ELSE e.seller_id
    END      AS seller_ex, -- метка, что продавец существует
    COUNT(*) AS count_of_zero_amt_purchases -- количество покупок с 0 стоимостью
FROM fantasy.events    AS e
    JOIN fantasy.items AS i USING(item_code)
WHERE e.amount = 0
group by i.game_items, seller_ex;

-- Анализ по месяцам. По данным видно, что с запуска игры (ну или как минимум внедрения торговли в игру) предмет скорее
-- всего раздавали, если, конечно, отсутствие seller_id, говорит о том, что покупка совершалась во внутриигровом
-- магазине.

WITH seller_exists AS -- выгружает кол-во транзакций с сущ. продавцом по месяцам
    (
        SELECT
            date_trunc('month', date::timestamp) AS months_ts, -- месяц в timestamp
            COUNT(*) AS exists -- кол-во покупок с сущ. продавцом
        FROM fantasy.events
        WHERE amount = 0 AND seller_id IS NOT NULL
        group by months_ts
    ),
    seller_dn_exists AS -- выгружает кол-во покупок с не сущ. продавцом
        (
            SELECT
                date_trunc('month', date::timestamp) AS months_ts,
                COUNT(*)                             AS dn_exists -- кол-во покупок с НЕ сущ. продавцом
            FROM fantasy.events
            WHERE amount = 0 AND seller_id IS NULL
            group by months_ts
        )

SELECT
    months_ts,
    EXTRACT(month FROM months_ts)
        + ( ( EXTRACT(year FROM months_ts)
        - MIN( EXTRACT(year FROM months_ts) ) OVER () ) * 12 ) AS months_num, -- номер месяца по счету
                                                                          -- (требовалось для визуализации)
    EXTRACT(year FROM months_ts)                               AS years,
    exists,
    dn_exists
FROM seller_exists
    FULL JOIN seller_dn_exists USING(months_ts)
ORDER BY months_num;

-- быстрая проверка на глобальный временной диапазон
SELECT
    MIN(date::timestamp),
    MAX(date::timestamp)
FROM fantasy.events;

-- 2.3: Популярные эпические предметы:

WITH non_zero_purchases AS (
    -- фильтруем покупки с ненулевой стоимостью
    SELECT
        e.item_code,
        e.id,
        e.amount
    FROM fantasy.events AS e
    WHERE e.amount > 0
),
     total_stats AS (
         SELECT
             COUNT(*)           AS total_purchases, -- кол-во покупок
             COUNT(DISTINCT id) AS total_buyers -- кол-во покупателей
         FROM non_zero_purchases
     )
SELECT
    i.game_items,
    COUNT(*)                                                          AS total_purchases, -- всего транзакций по предмету
    ROUND(COUNT(*)::numeric / ts.total_purchases, 4) * 100            AS purchases_share_percent, -- доля транзакций предмета
    COUNT(DISTINCT nzp.id)                                            AS unique_buyers, -- пользователи которые хотя бы раз покупали
    ROUND(COUNT(DISTINCT nzp.id)::numeric / ts.total_buyers, 4) * 100 AS buyer_share_percent --доля уникальных покупателей
FROM non_zero_purchases    AS nzp
    JOIN fantasy.items     AS i USING(item_code)
    CROSS JOIN total_stats AS ts
GROUP BY i.game_items, ts.total_purchases, ts.total_buyers
ORDER BY unique_buyers DESC; -- метрика оценки популярности у игроков (чем больше предмет был в ходу,
                            --  тем он популярнее.

-- запрос демонстрирует список предметов, которые ни разу не покупали
SELECT
    game_items
FROM fantasy.items       AS i
LEFT JOIN fantasy.events AS e USING(item_code)
WHERE transaction_id IS NULL;

-- Часть 2. Решение ad hoc-задачи
-- Задача: Зависимость активности игроков от расы персонажа:

WITH registered_players AS
         (
             -- количество зарегистрированных игроков по расам
             SELECT
                 race_id,
                 COUNT(*) AS total_players
             FROM fantasy.users
             GROUP BY race_id
         ),
     purchase_stats AS
         (
             -- все показатели, связанные с покупками (исключаем нулевые покупки везде)
             SELECT
                 u.race_id,
                 COUNT(DISTINCT CASE WHEN u.payer = 1 THEN e.id END) AS payers,
                 COUNT(DISTINCT e.id)                                AS buyers,
                 COUNT(*)                                            AS total_purchases,
                 SUM(e.amount)                                       AS total_amount
             FROM fantasy.events         AS e
                      JOIN fantasy.users AS u USING (id)
             WHERE e.amount > 0  -- отсекаем нулевые покупки
             GROUP BY u.race_id
         )
SELECT
    r.race,
    rp.total_players                                        AS players, -- количество игроков в расе
    ps.buyers,                                                          -- количество покупателей в расе
    ps.payers,                                                          -- количество плательщиков среди покупателей в расе
    ROUND(ps.buyers::numeric / rp.total_players * 100, 2)   AS share_of_buyers, -- доля покупателей в расе
    ROUND(ps.payers::numeric / ps.buyers * 100, 2)          AS share_of_payers, -- доля плательщиков среди покупателей в расе
    ROUND(ps.total_purchases::numeric / ps.buyers, 2)       AS avg_count_of_purchases, -- среднее кол-во покупок
    ROUND(ps.total_amount::numeric / ps.total_purchases, 2) AS avg_purchase_amount, -- среднее стоимости покупки
    ROUND(ps.total_amount::numeric / ps.buyers, 2)          AS avg_total_amt_per_buyer -- среднее суммарного значения всех покупок
FROM registered_players      AS rp
         JOIN purchase_stats AS ps USING (race_id)
         JOIN fantasy.race   AS r  USING (race_id)
ORDER BY avg_purchase_amount DESC;