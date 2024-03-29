-- name: GetCities :many
SELECT name FROM city;

-- name: GetSectionsByCity :many
SELECT section.name
FROM section
LEFT JOIN city ON (section.city_id = city.id)
WHERE city.name = @city_name;

-- name: GetSectionsWithCity :many
SELECT section.name AS section, city.name AS city
FROM section
LEFT JOIN city ON (section.city_id = city.id);

-- name: GetSection :one
SELECT *
FROM section
LEFT JOIN city ON (section.city_id = city.id)
WHERE city.name = @city
AND section.name = @section;

-- name: GetHourses :many
WITH duplicate_conditions AS (
    SELECT MIN(id) AS id, section_id, address, age, area
    FROM hourse
    WHERE link LIKE 'https://sale.591.com.tw/home%'
    AND updated_at > CURRENT_TIMESTAMP - INTERVAL '7 day'
    GROUP BY section_id, address, age, area
    HAVING count(1) > 1
),
duplicate AS (
    SELECT hourse.id
    FROM hourse
    INNER JOIN duplicate_conditions ON(
            hourse.section_id = duplicate_conditions.section_id
        AND hourse.address = duplicate_conditions.address
        AND hourse.age = duplicate_conditions.age
        AND hourse.area = duplicate_conditions.area
        AND hourse.link LIKE 'https://sale.591.com.tw/home%'
    )
    WHERE hourse.id NOT IN (SELECT id FROM duplicate_conditions)
    AND hourse.updated_at > CURRENT_TIMESTAMP - INTERVAL '7 day'
),
candidates AS (
    SELECT hourse.id
    FROM hourse
    LEFT JOIN section ON (section.id=hourse.section_id)
    LEFT JOIN city ON (city.id=section.city_id)
    WHERE hourse.updated_at > CURRENT_TIMESTAMP - INTERVAL '7 day'
    AND hourse.id NOT IN (SELECT id FROM duplicate)
    AND hourse.main_area IS NOT NULL
    AND (city.name IN (@city) OR COALESCE(@city, '') = '')
    AND (section.name IN (@section) OR COALESCE(@section, '') = '')
    AND (@max_price = 0 OR hourse.price < @max_price)
    AND (hourse.age < @age OR COALESCE(@age, '') = '')
    AND (@min_main_area = 0 OR hourse.main_area > @min_main_area :: DECIMAL)
    AND (hourse.shape IN (@shape) OR COALESCE(@shape, '') = '')
    AND (
        CASE
        WHEN hourse.shape = '公寓' THEN hourse.current_floor = '3F'
        ELSE TRUE
        END
    )
    AND hourse.current_floor != hourse.total_floor
    AND hourse.current_floor NOT IN ('-1F', 'B1F', 'B1', '頂樓加蓋')
)
SELECT
    hourse.id,
    CONCAT(city.name, section.name, hourse.address) :: TEXT AS address,
    city.name AS city,
    section.name AS section,
    hourse.price,
    hourse.current_floor,
    CONCAT(hourse.current_floor, '/', hourse.total_floor) :: TEXT AS floor,
    hourse.shape,
    hourse.age,
    hourse.main_area,
    hourse.area,
    hourse.layout,
    section.name AS section,
    hourse.link,
    COALESCE(hourse.commit, '') AS commit,
    hourse.created_at,
    (SELECT COUNT(1) FROM candidates) AS total_count
FROM hourse
INNER JOIN candidates USING(id)
LEFT JOIN section ON (section.id=hourse.section_id)
LEFT JOIN city ON (city.id=section.city_id)
ORDER BY hourse.age, hourse.price, hourse.main_area;
-- OFFSET @offset_param :: INTEGER LIMIT @limit_param :: INTEGER;

-- name: UpsertHourse :exec
INSERT INTO hourse (
    section_id, link, layout, address, price, current_floor, total_floor,
    shape, age, area, main_area, raw)
VALUES (
    @section_id, @link, @layout, @address, @price, @current_floor,
    @total_floor, @shape, @age, @area, @main_area, @raw)
ON CONFLICT (link)
DO UPDATE
SET updated_at = CURRENT_TIMESTAMP, price = EXCLUDED.price;