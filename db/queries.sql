-- КОЛИЧЕСТВО ПОПАДАНИЙ И ПРОМАХОВ ПО КАЖДОЙ СТАНЦИИ (ЕСЛИ БЫЛ ХОТЯ БЫ ОДИН ВЫСТРЕЛ)

sqlite3 vkr.db <<EOF
.headers on
.mode table
SELECT
    service_id,
    COUNT(shots.id) AS total_shots,
    SUM(CASE WHEN is_hit_target = 1 THEN 1 ELSE 0 END) AS hits,
    SUM(CASE WHEN is_hit_target = 0 THEN 1 ELSE 0 END) AS misses
FROM shots
GROUP BY service_id
HAVING COUNT(*) > 0;
EOF


-- ТОП СТАНЦИЙ ПО КОЛИЧЕСТВУ УНИЧТОЖЕНИЙ
sqlite3 vkr.db <<EOF
.headers on
.mode table
SELECT
    service_id,
    COUNT(*) AS hit_count
FROM shots
WHERE is_hit_target = 1
GROUP BY service_id
ORDER BY hit_count DESC;
EOF

-- ТОП СТАНЦИЙ ПО МЕТКОСТИ (ПРОЦЕНТУ УНИЧТОЖЕНИЙ СРЕДИ ВСЕХ ВЫСТРЕЛОВ)
sqlite3 vkr.db <<EOF
.headers on
.mode table
SELECT
    service_id,
    COUNT(shots.id) AS total_shots,
    SUM(CASE WHEN shots.is_hit_target = 1 THEN 1 ELSE 0 END) AS total_hits,
    ROUND(100.0 * SUM(CASE WHEN is_hit_target = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS accuracy_percent
FROM shots
GROUP BY service_id
ORDER BY accuracy_percent DESC;
EOF

-- КОЛИЧЕСТВО БП У КАЖДОЙ СТАНЦИИ
sqlite3 vkr.db <<EOF
.headers on
.mode table
WITH last_ammo AS (
    SELECT
        service_id,
        count,
        ROW_NUMBER() OVER (PARTITION BY service_id ORDER BY timestamp DESC) AS rn,
        timestamp
    FROM ammo
),
shots_count as (
    SELECT
        service_id,
        COUNT(*) AS shot_count,
        timestamp
    FROM shots
    GROUP BY service_id
)

SELECT
    l.service_id,
    l.count as initial_ammo,
    sc.shot_count,
    (l.count - COALESCE(sc.shot_count, 0)) AS current_ammo
FROM last_ammo l
LEFT JOIN shots_count sc 
    ON l.service_id = sc.service_id
    and sc.timestamp >= l.timestamp
WHERE l.rn = 1;
EOF

-- КОЛИЧЕСТВО СБИТЫХ ЦЕЛЕЙ У КАЖДОЙ СТАНЦИИ ЗРДН ЗА ИНТЕРВАЛ ВРЕМЕНИ
sqlite3 vkr.db <<EOF
.headers on
.mode table
SELECT
    service_id,
    COUNT(*) AS destroyed_targets
FROM shots
WHERE
    is_hit_target = 1
    AND timestamp BETWEEN '26-04 00:00:00.000' AND '28-04 23:59:59.999'
GROUP BY service_id
ORDER BY destroyed_targets DESC;
EOF

-- КОЛИЧЕСТВО ЦЕЛЕЙ, НАПРАВЛЯЮЩИХСЯ В СТОРОНУ СПРО
sqlite3 vkr.db <<EOF
.headers on
.mode table
SELECT
    COUNT(*) AS spro_targets,
    GROUP_CONCAT(id) AS target_ids
FROM targets
WHERE is_move_to_spro = 1;
EOF